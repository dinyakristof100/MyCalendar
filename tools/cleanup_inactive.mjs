// Inaktív felhasználók takarítása — 6 hónap után törli az adatot ÉS a fiókot.
//
// Ezt a GitHub Action (.github/workflows/cleanup-inactive.yml) futtatja ütemezve,
// a felhasználó távollétében is. Az app minden felhő-íráskor a `ttl` mezőt
// now+183 napra tolja (lib/core/cloud_sync.dart); ami itt már lejárt, azt a
// felhasználó fél éve nem nyitotta meg -> mehet.
//
// Spark-kompatibilis: sima Firestore olvasás/törlés + Auth-fiók törlés az Admin
// SDK-val — ezek a free tier alatt vannak (a fizetős dolog a TTL-SZABÁLY volt).

import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const b64 = process.env.FIREBASE_SA_B64;
if (!b64) {
  console.error('Hiányzik a FIREBASE_SA_B64 secret (service-account kulcs base64-ben).');
  process.exit(1);
}

const sa = JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
const app = initializeApp({ credential: cert(sa) });
// A named DB — NEM a (default). Lásd project-status memória.
const db = getFirestore(app, 'mycalendardb');
const auth = getAuth(app);

const now = Timestamp.now();
// A ttl nélküli (feature előtti) dokumentumok kimaradnak a szűrőből — nem baj,
// a következő appindításkor kapnak ttl-t. ponytail: nincs külön migráció rájuk.
const expired = await db.collection('users').where('ttl', '<', now).get();

let deleted = 0;
for (const doc of expired.docs) {
  const uid = doc.id; // a dokumentum azonosítója a Firebase Auth uid
  await doc.ref.delete();
  try {
    await auth.deleteUser(uid);
  } catch (e) {
    // A fiók már törölve lehet (pl. a user maga tette) — az adat viszont most ment.
    console.warn(`Auth-fiók törlése kihagyva (${uid}): ${e.code ?? e.message}`);
  }
  deleted++;
  console.log(`törölve: ${uid}`);
}

console.log(`Kész: ${deleted} lejárt fiók törölve (${expired.size} találat).`);
