import fs from 'node:fs';
import path from 'node:path';

export function loadConfig(env = process.env) {
  const port = Number(env.PORT || 3000);
  return {
    port,
    // Address the iPhone uses to reach this server; photo links are built from it.
    publicUrl: (env.PUBLIC_URL || `http://localhost:${port}`).replace(/\/+$/, ''),
    dataDir: path.resolve(env.DATA_DIR || 'data'),
    week: {
      // Fixed UTC offset of the friends' timezone. Moscow = +180.
      tzOffsetMinutes: Number(env.TZ_OFFSET_MINUTES ?? 180),
      // The week closes on this local day (1 = Monday … 7 = Sunday) and hour.
      endDay: Number(env.WEEK_END_DAY ?? 7),
      endHour: Number(env.WEEK_END_HOUR ?? 21),
    },
    reminderHoursBefore: Number(env.REMINDER_HOURS_BEFORE ?? 3),
    maxCircleMembers: Number(env.MAX_CIRCLE_MEMBERS ?? 30),
    apns: readApnsConfig(env),
  };
}

function readApnsConfig(env) {
  let keyPem = env.APNS_KEY ? env.APNS_KEY.replace(/\\n/g, '\n') : null;
  if (!keyPem && env.APNS_KEY_PATH) keyPem = fs.readFileSync(env.APNS_KEY_PATH, 'utf8');
  if (!keyPem) return null;
  const missing = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC'].filter((k) => !env[k]);
  if (missing.length) throw new Error(`APNs key is set but ${missing.join(', ')} missing`);
  return { keyPem, keyId: env.APNS_KEY_ID, teamId: env.APNS_TEAM_ID, topic: env.APNS_TOPIC };
}
