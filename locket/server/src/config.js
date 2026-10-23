import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export function loadConfig(env = process.env) {
  const port = Number(env.PORT || 3000);
  const dataDir = path.resolve(env.DATA_DIR || 'data');
  return {
    port,
    // Address the iPhone uses to reach this server; photo links are built from it.
    publicUrl: (env.PUBLIC_URL || `http://localhost:${port}`).replace(/\/+$/, ''),
    dataDir,
    // Secret for password keys. Lose it and nobody can sign in again.
    passwordPepper: env.PASSWORD_PEPPER || readPepperFile(dataDir),
    // Behind Caddy: the client address is the first X-Forwarded-For entry.
    trustProxy: env.TRUST_PROXY === '1',
    maxFriends: Number(env.MAX_FRIENDS ?? 100),
    week: {
      // Fixed UTC offset of the friends' timezone. Moscow = +180.
      tzOffsetMinutes: Number(env.TZ_OFFSET_MINUTES ?? 180),
      // The week closes on this local day (1 = Monday … 7 = Sunday) and hour.
      endDay: Number(env.WEEK_END_DAY ?? 7),
      endHour: Number(env.WEEK_END_HOUR ?? 21),
    },
    reminderHoursBefore: Number(env.REMINDER_HOURS_BEFORE ?? 3),
    // «Кто лучше?» arrives once a day at a random moment between these local hours.
    duel: {
      fromHour: Number(env.DUEL_FROM_HOUR ?? 11),
      toHour: Number(env.DUEL_TO_HOUR ?? 21),
    },
    apns: readApnsConfig(env),
  };
}

// <DATA_DIR>/pepper: created once with 32 random bytes, then only read. It sits
// next to the database so a backup of the data folder carries both.
function readPepperFile(dataDir) {
  const file = path.join(dataDir, 'pepper');
  fs.mkdirSync(dataDir, { recursive: true });
  try {
    fs.writeFileSync(file, crypto.randomBytes(32).toString('hex'), { flag: 'wx', mode: 0o600 });
  } catch (err) {
    if (err.code !== 'EEXIST') throw err;
  }
  const pepper = fs.readFileSync(file, 'utf8').trim();
  if (!pepper) throw new Error(`${file} is empty: restore it from a backup, otherwise nobody can sign in`);
  return pepper;
}

function readApnsConfig(env) {
  let keyPem = env.APNS_KEY ? env.APNS_KEY.replace(/\\n/g, '\n') : null;
  if (!keyPem && env.APNS_KEY_PATH) keyPem = fs.readFileSync(env.APNS_KEY_PATH, 'utf8');
  if (!keyPem) return null;
  const missing = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC'].filter((k) => !env[k]);
  if (missing.length) throw new Error(`APNs key is set but ${missing.join(', ')} missing`);
  return { keyPem, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC };
}
