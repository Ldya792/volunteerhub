// seed.js: adds sample events to Firestore for demos and testing.
// Safe to run more than once: fixed IDs mean no duplicates.
const { Firestore, FieldValue } = require('@google-cloud/firestore');

const db = new Firestore({ projectId: process.env.PROJECT_ID });

const events = [
  { id: 'sample-park-cleanup', title: 'Community Park Cleanup',
    date: '2026-10-17', location: 'Shedd Park, Lowell, MA' },
  { id: 'sample-blood-drive', title: 'Campus Blood Drive',
    date: '2026-10-24', location: 'University Crossing, UMass Lowell' },
  { id: 'sample-food-bank', title: 'Food Bank Sorting & Packing',
    date: '2026-11-07', location: 'Merrimack Valley Food Bank, Lowell, MA' },
];

async function seed() {
  for (const e of events) {
    const { id, ...data } = e;
    await db.collection('events').doc(id).set({
      ...data,
      flyer: null,                          // no image, so the 🌱 placeholder shows
      createdAt: FieldValue.serverTimestamp(),
    });
    console.log(`Seeded: ${e.title} (${e.date})`);
  }
}

seed().catch((err) => { console.error(err.message); process.exit(1); });
