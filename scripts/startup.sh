#!/usr/bin/env bash
# VolunteerHub VM startup script: runs as root on EVERY boot.
# Written to be safe to run again (idempotent).
set -euo pipefail
export HOME=/root
export DEBIAN_FRONTEND=noninteractive

APP_DIR=/opt/volunteerhub
APP_USER=volunteerhub
MD=http://metadata.google.internal/computeMetadata/v1
mdget() { curl -sf -H "Metadata-Flavor: Google" "$MD/$1"; }

# --- 1. Who am I? Ask the metadata server (no hard-coded project) ---
PROJECT_ID=$(mdget project/project-id)
RELEASE_BUCKET="${PROJECT_ID}-releases"
FLYER_BUCKET="${PROJECT_ID}-flyers"
echo "[startup] project=${PROJECT_ID}"

# --- 2. Install Nginx and Node.js 24 (only if missing) ---
if ! command -v nginx >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y nginx
fi
if ! node --version 2>/dev/null | grep -q '^v24\.'; then
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
fi

# --- 3. Dedicated app user: no password, no login shell ---
id "$APP_USER" >/dev/null 2>&1 || \
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"

# --- 4. Download the current release with the VM's service account ---
TOKEN=$(mdget instance/service-accounts/default/token \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])')
curl -sf -H "Authorization: Bearer ${TOKEN}" -o /tmp/release.tar.gz \
  "https://storage.googleapis.com/storage/v1/b/${RELEASE_BUCKET}/o/current.tar.gz?alt=media"

# --- 5. Unpack into a new folder, install deps, then swap it in ---
rm -rf "${APP_DIR}.new" && mkdir -p "${APP_DIR}.new"
tar -xzf /tmp/release.tar.gz -C "${APP_DIR}.new"
cd "${APP_DIR}.new"
npm ci --omit=dev
cd /
rm -rf "$APP_DIR" && mv "${APP_DIR}.new" "$APP_DIR"
# Code stays owned by root: the app can READ its code but never CHANGE it

# --- 6. Run the app as a systemd service ---
cat > /etc/systemd/system/volunteerhub.service <<UNIT
[Unit]
Description=VolunteerHub web app
After=network-online.target
Wants=network-online.target

[Service]
User=${APP_USER}
WorkingDirectory=${APP_DIR}
Environment=NODE_ENV=production
Environment=PORT=3000
Environment=PROJECT_ID=${PROJECT_ID}
Environment=FLYER_BUCKET=${FLYER_BUCKET}
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable volunteerhub
systemctl restart volunteerhub

# --- 7. Nginx: public port 80 -> app on localhost:3000 ---
cat > /etc/nginx/sites-available/volunteerhub <<'NGINX'
server {
    listen 80 default_server;
    server_name _;
    client_max_body_size 6m;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 30s;
    }
}
NGINX
ln -sf /etc/nginx/sites-available/volunteerhub /etc/nginx/sites-enabled/volunteerhub
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable nginx
systemctl restart nginx

# --- 8. Wait until the app answers its health check ---
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1/health >/dev/null; then
    echo "[startup] VolunteerHub is healthy"
    exit 0
  fi
  sleep 2
done
echo "[startup] WARNING: app did not become healthy in 60s"
