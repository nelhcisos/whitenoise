import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createApnsClient } from './apns.js';
import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { openDb } from './db.js';

const config = loadConfig();
fs.mkdirSync(config.dataDir, { recursive: true });
const db = openDb(path.join(config.dataDir, 'locket.db'));

const apns = config.apns ? createApnsClient(config.apns) : null;
if (!apns) console.warn('APNs не настроен (APNS_KEY_PATH и др.) — пуши будут только печататься в лог.');

const app = createApp({ config, db, apns });
const server = http.createServer(app.handle);

const tick = () => app.runDue().catch((err) => console.error('scheduler', err));
const timer = setInterval(tick, 30_000);
tick();

server.listen(config.port, () => {
  console.log(`Locket server on :${config.port}, public URL ${config.publicUrl}, data in ${config.dataDir}`);
});

function shutdown() {
  clearInterval(timer);
  server.close(() => {
    apns?.close();
    db.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 5000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
