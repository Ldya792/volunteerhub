// VolunteerHub: volunteer event sign-up website
const express = require('express');
const cookieSession = require('cookie-session');
const multer = require('multer');
const crypto = require('crypto');
const os = require('os');
const path = require('path');
const { Firestore, FieldValue } = require('@google-cloud/firestore');
const { Storage } = require('@google-cloud/storage');
const { SecretManagerServiceClient } = require('@google-cloud/secret-manager');

// ---------- Settings (can be overridden with environment variables) ----------
const PROJECT_ID = process.env.PROJECT_ID || 'volunteerhub-lw-2026';
const FLYER_BUCKET = process.env.FLYER_BUCKET || `${PROJECT_ID}-flyers`;
const PORT = Number(process.env.PORT) || 3000;
const SERVER_NAME = os.hostname().split('.')[0];

// ---------- Google Cloud clients: credentials come from ADC, no keys ----------
const db = new Firestore({ projectId: PROJECT_ID });
const bucket = new Storage({ projectId: PROJECT_ID }).bucket(FLYER_BUCKET);
const secrets = new SecretManagerServiceClient();

async function readSecret(name) {
  const [version] = await secrets.accessSecretVersion({
    name: `projects/${PROJECT_ID}/secrets/${name}/versions/latest`,
  });
  return version.payload.data.toString('utf8');
}

// ---------- Helpers ----------
// Escape user text before putting it in HTML (prevents cross-site scripting)
function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Compare passwords in constant time (prevents timing attacks)
function sameText(a, b) {
  const hashA = crypto.createHash('sha256').update(String(a)).digest();
  const hashB = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(hashA, hashB);
}

function dateBadge(date) {
  const d = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return '';
  const month = d.toLocaleString('en-US', { month: 'short', timeZone: 'UTC' });
  return `<div class="date-badge"><span>${month}</span><strong>${d.getUTCDate()}</strong></div>`;
}

function page(title, body) {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHtml(title)} | VolunteerHub</title>
  <link rel="stylesheet" href="/styles.css">
</head>
<body>
  <header class="site-header">
    <div class="container nav">
      <a class="brand" href="/">🤝 VolunteerHub</a>
      <nav><a href="/#events">Events</a><a href="/admin">Admin</a></nav>
    </div>
  </header>
  <main>${body}</main>
  <footer class="site-footer">
    <div class="container">
      <p>VolunteerHub connects volunteers with local community events.</p>
      <p class="server">Served by ${escapeHtml(SERVER_NAME)} · Hosted on Google Cloud</p>
    </div>
  </footer>
</body>
</html>`;
}

function panel(title, inner) {
  return page(title, `<section class="container narrow"><div class="panel">${inner}</div></section>`);
}

function requireAdmin(req, res, next) {
  if (req.session && req.session.isAdmin) return next();
  res.redirect('/admin/login');
}

// Flyer uploads: images only, max 5 MB, kept in memory and then sent to Cloud Storage
const IMAGE_TYPES = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/gif': '.gif', 'image/webp': '.webp' };
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => cb(null, Boolean(IMAGE_TYPES[file.mimetype])),
});

async function start() {
  // Read both secrets from Secret Manager once, at startup
  const sessionSecret = await readSecret('volunteerhub-session-secret');
  const adminPassword = await readSecret('volunteerhub-admin-password');

  const app = express();
  app.set('trust proxy', true); // requests arrive through the load balancer
  app.use(express.static(path.join(__dirname, 'public'), { maxAge: '1h' }));
  app.use(express.urlencoded({ extended: false }));
  app.use(cookieSession({
    name: 'vh_session',
    keys: [sessionSecret], // the same secret on every VM, so any VM can verify the cookie
    maxAge: 2 * 60 * 60 * 1000, // 2 hours
    httpOnly: true,
    sameSite: 'lax',
  }));

  // Health check for the load balancer: fast, and does not depend on Firestore
  app.get('/health', (req, res) => res.type('text').send('OK'));

  // ---------- Public pages ----------
  app.get('/', async (req, res) => {
    const snapshot = await db.collection('events').orderBy('date').get();
    let message = '';
    if (req.query.signed) message = '<p class="notice">Thank you! Your sign-up was saved.</p>';
    if (req.query.error) message = '<p class="error">Please enter a valid name and email.</p>';

    const cards = snapshot.docs.map((doc) => {
      const e = doc.data();
      const image = e.flyer
        ? `<img class="flyer" src="/flyers/${encodeURIComponent(e.flyer)}" alt="Flyer for ${escapeHtml(e.title)}">`
        : '<div class="flyer placeholder">🌱</div>';
      return `<article class="card">
        ${image}
        <div class="card-body">
          <div class="card-head">
            ${dateBadge(e.date)}
            <div>
              <h3>${escapeHtml(e.title)}</h3>
              <p class="meta">📍 ${escapeHtml(e.location)}</p>
            </div>
          </div>
          <form class="signup" method="post" action="/signup">
            <input type="hidden" name="eventId" value="${escapeHtml(doc.id)}">
            <input name="name" placeholder="Your name" required maxlength="100">
            <input name="email" type="email" placeholder="Your email" required maxlength="200">
            <button type="submit">Sign up</button>
          </form>
        </div>
      </article>`;
    }).join('');

    const hero = `<section class="hero"><div class="container">
      <h1>Make a difference in your community</h1>
      <p>Find a volunteer event near you and sign up in seconds.</p>
      <a class="button" href="#events">See upcoming events</a>
    </div></section>`;

    const events = `<section id="events" class="container">
      <h2 class="section-title">Upcoming events</h2>
      ${message}
      ${cards ? `<div class="grid">${cards}</div>` : '<div class="empty">No upcoming events yet. Check back soon!</div>'}
    </section>`;

    res.send(page('Events', hero + events));
  });

  app.post('/signup', async (req, res) => {
    const name = String(req.body.name || '').trim();
    const email = String(req.body.email || '').trim();
    const eventId = String(req.body.eventId || '');
    const validEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
    if (!name || name.length > 100 || !validEmail || email.length > 200 || !eventId) {
      return res.redirect('/?error=1#events');
    }
    const event = await db.collection('events').doc(eventId).get();
    if (!event.exists) return res.redirect('/?error=1#events');

    await db.collection('signups').add({
      name,
      email,
      eventId,
      eventTitle: event.get('title'),
      servedBy: SERVER_NAME,
      createdAt: FieldValue.serverTimestamp(),
    });
    res.redirect('/?signed=1#events');
  });

  // Stream a flyer from the private bucket through the app
  app.get('/flyers/:name', async (req, res) => {
    const name = req.params.name;
    if (!/^[\w.-]+$/.test(name)) return res.status(404).send('Not found');
    const file = bucket.file(`flyers/${name}`);
    const [exists] = await file.exists();
    if (!exists) return res.status(404).send('Not found');
    const [meta] = await file.getMetadata();
    res.type(meta.contentType || 'application/octet-stream');
    res.set('Cache-Control', 'public, max-age=3600');
    file.createReadStream().on('error', () => res.end()).pipe(res);
  });

  // ---------- Admin pages ----------
  app.get('/admin/login', (req, res) => {
    const error = req.query.error ? '<p class="error">Wrong password.</p>' : '';
    res.send(panel('Admin login', `
      <h2>Admin login</h2>
      <p class="meta">Event organizers only.</p>
      ${error}
      <form method="post" action="/admin/login">
        <input name="password" type="password" placeholder="Admin password" required>
        <button type="submit">Log in</button>
      </form>`));
  });

  app.post('/admin/login', (req, res) => {
    if (sameText(req.body.password || '', adminPassword)) {
      req.session.isAdmin = true;
      return res.redirect('/admin');
    }
    res.redirect('/admin/login?error=1');
  });

  app.post('/admin/logout', (req, res) => {
    req.session = null;
    res.redirect('/');
  });

  app.get('/admin', requireAdmin, async (req, res) => {
    const recent = await db.collection('signups').orderBy('createdAt', 'desc').limit(20).get();
    const rows = recent.docs.map((doc) => {
      const s = doc.data();
      return `<tr><td>${escapeHtml(s.name)}</td><td>${escapeHtml(s.email)}</td>
        <td>${escapeHtml(s.eventTitle)}</td><td>${escapeHtml(s.servedBy)}</td></tr>`;
    }).join('');
    const message = req.query.created ? '<p class="notice">Event created.</p>' : '';

    res.send(page('Admin', `<section class="container narrow">
      ${message}
      <div class="panel">
        <h2>Create an event</h2>
        <form method="post" action="/admin/events" enctype="multipart/form-data">
          <input name="title" placeholder="Event title" required maxlength="100">
          <input name="date" type="date" required>
          <input name="location" placeholder="Location" required maxlength="150">
          <label>Flyer image (optional, max 5 MB)</label>
          <input name="flyer" type="file" accept="image/*">
          <button type="submit">Create event</button>
        </form>
      </div>
      <div class="panel">
        <h2>Recent sign-ups</h2>
        <div class="table-wrap">
          <table><tr><th>Name</th><th>Email</th><th>Event</th><th>Served by</th></tr>${rows}</table>
        </div>
      </div>
      <form method="post" action="/admin/logout"><button class="secondary" type="submit">Log out</button></form>
    </section>`));
  });

  app.post('/admin/events', requireAdmin, upload.single('flyer'), async (req, res) => {
    const title = String(req.body.title || '').trim();
    const date = String(req.body.date || '').trim();
    const location = String(req.body.location || '').trim();
    if (!title || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !location) {
      return res.status(400).send(panel('Error', '<p class="error">Please fill in all fields.</p>'));
    }

    let flyer = null;
    if (req.file) {
      flyer = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}${IMAGE_TYPES[req.file.mimetype]}`;
      await bucket.file(`flyers/${flyer}`).save(req.file.buffer, {
        contentType: req.file.mimetype,
        resumable: false,
      });
    }

    await db.collection('events').add({ title, date, location, flyer, createdAt: FieldValue.serverTimestamp() });
    res.redirect('/admin?created=1');
  });

  // ---------- Error handler: log details, show a simple message ----------
  app.use((err, req, res, next) => {
    console.error(err);
    res.status(500).send(panel('Error', '<p class="error">Something went wrong. Please try again.</p>'));
  });

  app.listen(PORT, () => {
    console.log(`VolunteerHub listening on port ${PORT} (server ${SERVER_NAME})`);
  });
}

start().catch((err) => {
  console.error('Failed to start:', err.message);
  process.exit(1);
});

