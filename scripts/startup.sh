#!/bin/bash
# VolunteerHub VM startup script: installs Nginx and a test page
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx

VM_NAME=$(hostname)

cat > /var/www/html/index.html <<EOF
<h1>VolunteerHub</h1>
<p>Served by ${VM_NAME}</p>
EOF

echo "OK" > /var/www/html/health

systemctl enable --now nginx

