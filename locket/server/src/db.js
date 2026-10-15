import { DatabaseSync } from 'node:sqlite';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS circles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  invite_code TEXT NOT NULL UNIQUE,
  owner_id TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  circle_id TEXT REFERENCES circles(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS users_circle ON users(circle_id);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS devices (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  env TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_user ON devices(user_id);
CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_id TEXT NOT NULL,
  caption TEXT,
  file TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS photos_circle_created ON photos(circle_id, created_at DESC);
CREATE INDEX IF NOT EXISTS photos_week ON photos(week_id, circle_id);
CREATE TABLE IF NOT EXISTS reactions (
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('creative', 'funny', 'wild')),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (photo_id, user_id, kind)
);
CREATE TABLE IF NOT EXISTS stars (
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  value INTEGER NOT NULL CHECK (value BETWEEN 1 AND 3),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (photo_id, user_id)
);
CREATE TABLE IF NOT EXISTS weeks (
  circle_id TEXT NOT NULL REFERENCES circles(id) ON DELETE CASCADE,
  week_id TEXT NOT NULL,
  closed_at INTEGER NOT NULL,
  results TEXT NOT NULL,
  PRIMARY KEY (circle_id, week_id)
);
CREATE TABLE IF NOT EXISTS jobs (
  key TEXT PRIMARY KEY,
  done_at INTEGER NOT NULL
);
`;

export function openDb(file) {
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  db.exec(SCHEMA);
  return db;
}

export function createStore(db) {
  const q = (sql) => db.prepare(sql);
  const placeholders = (n) => Array(n).fill('?').join(',');

  const photoRow = (r) =>
    r && {
      id: r.id,
      circleId: r.circle_id,
      authorId: r.author_id,
      authorName: r.author_name,
      weekId: r.week_id,
      caption: r.caption,
      file: r.file,
      createdAt: r.created_at,
    };
  const userRow = (r) => r && { id: r.id, email: r.email, name: r.name, circleId: r.circle_id, passwordHash: r.password_hash };
  const circleRow = (r) => r && { id: r.id, name: r.name, inviteCode: r.invite_code, ownerId: r.owner_id };
  const PHOTO_SELECT = 'SELECT p.*, u.name AS author_name FROM photos p JOIN users u ON u.id = p.author_id';

  return {
    transaction(fn) {
      db.exec('BEGIN IMMEDIATE');
      try {
        const result = fn();
        db.exec('COMMIT');
        return result;
      } catch (err) {
        db.exec('ROLLBACK');
        throw err;
      }
    },

    // Users & sessions
    createUser({ id, email, name, passwordHash, now }) {
      q('INSERT INTO users (id, email, name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)').run(id, email, name, passwordHash, now);
    },
    userByEmail: (email) => userRow(q('SELECT * FROM users WHERE email = ?').get(email)),
    user: (id) => userRow(q('SELECT * FROM users WHERE id = ?').get(id)),
    renameUser: (id, name) => q('UPDATE users SET name = ? WHERE id = ?').run(name, id),
    setUserCircle: (id, circleId) => q('UPDATE users SET circle_id = ? WHERE id = ?').run(circleId, id),
    createSession: (tokenHash, userId, now) =>
      q('INSERT INTO sessions (token_hash, user_id, created_at) VALUES (?, ?, ?)').run(tokenHash, userId, now),
    userBySession: (tokenHash) =>
      userRow(q('SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?').get(tokenHash)),
    deleteSession: (tokenHash) => q('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash),

    // Devices (APNs tokens)
    upsertDevice: (token, userId, env, now) =>
      q(
        `INSERT INTO devices (token, user_id, env, updated_at) VALUES (?, ?, ?, ?)
         ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, env = excluded.env, updated_at = excluded.updated_at`,
      ).run(token, userId, env, now),
    deleteDevice: (token, userId) =>
      userId
        ? q('DELETE FROM devices WHERE token = ? AND user_id = ?').run(token, userId)
        : q('DELETE FROM devices WHERE token = ?').run(token),
    devicesForUsers(userIds) {
      if (!userIds.length) return [];
      return q(`SELECT token, env, user_id AS userId FROM devices WHERE user_id IN (${placeholders(userIds.length)})`).all(...userIds);
    },

    // Circles
    createCircle({ id, name, inviteCode, ownerId, now }) {
      q('INSERT INTO circles (id, name, invite_code, owner_id, created_at) VALUES (?, ?, ?, ?, ?)').run(id, name, inviteCode, ownerId, now);
    },
    circle: (id) => circleRow(q('SELECT * FROM circles WHERE id = ?').get(id)),
    circleByCode: (code) => circleRow(q('SELECT * FROM circles WHERE invite_code = ?').get(code)),
    renameCircle: (id, name) => q('UPDATE circles SET name = ? WHERE id = ?').run(name, id),
    members: (circleId) => q('SELECT id, name FROM users WHERE circle_id = ? ORDER BY created_at').all(circleId),

    // Photos
    insertPhoto({ id, circleId, authorId, weekId, caption, file, now }) {
      q('INSERT INTO photos (id, circle_id, author_id, week_id, caption, file, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)').run(
        id, circleId, authorId, weekId, caption, file, now,
      );
    },
    photo: (id) => photoRow(q(`${PHOTO_SELECT} WHERE p.id = ?`).get(id)),
    latestFromOthers: (circleId, userId) =>
      photoRow(q(`${PHOTO_SELECT} WHERE p.circle_id = ? AND p.author_id <> ? ORDER BY p.created_at DESC LIMIT 1`).get(circleId, userId)),
    deletePhoto: (id) => q('DELETE FROM photos WHERE id = ?').run(id),
    feed(circleId, before, limit) {
      return q(`${PHOTO_SELECT} WHERE p.circle_id = ? AND p.created_at < ? ORDER BY p.created_at DESC LIMIT ?`)
        .all(circleId, before, limit)
        .map(photoRow);
    },
    reactionsFor(photoIds) {
      if (!photoIds.length) return [];
      return q(
        `SELECT r.photo_id AS photoId, r.user_id AS userId, r.kind, u.name
         FROM reactions r JOIN users u ON u.id = r.user_id
         WHERE r.photo_id IN (${placeholders(photoIds.length)}) ORDER BY r.created_at, r.rowid`,
      ).all(...photoIds);
    },
    // Returns true when the reaction state actually changed.
    setReaction(photoId, userId, kind, on, now) {
      const res = on
        ? q('INSERT OR IGNORE INTO reactions (photo_id, user_id, kind, created_at) VALUES (?, ?, ?, ?)').run(photoId, userId, kind, now)
        : q('DELETE FROM reactions WHERE photo_id = ? AND user_id = ? AND kind = ?').run(photoId, userId, kind);
      return res.changes > 0;
    },
    kindsBy: (photoId, userId) =>
      q('SELECT kind FROM reactions WHERE photo_id = ? AND user_id = ? ORDER BY created_at, rowid').all(photoId, userId).map((r) => r.kind),
    starsFor(photoIds) {
      if (!photoIds.length) return [];
      return q(
        `SELECT s.photo_id AS photoId, s.user_id AS userId, s.value, u.name
         FROM stars s JOIN users u ON u.id = s.user_id
         WHERE s.photo_id IN (${placeholders(photoIds.length)}) ORDER BY s.updated_at, s.rowid`,
      ).all(...photoIds);
    },
    starsBy: (photoId, userId) => q('SELECT value FROM stars WHERE photo_id = ? AND user_id = ?').get(photoId, userId)?.value ?? 0,
    // Returns true when the rating actually changed. value 0 clears it.
    setStars(photoId, userId, value, now) {
      const res = value
        ? q(
            `INSERT INTO stars (photo_id, user_id, value, updated_at) VALUES (?, ?, ?, ?)
             ON CONFLICT(photo_id, user_id) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
             WHERE stars.value <> excluded.value`,
          ).run(photoId, userId, value, now)
        : q('DELETE FROM stars WHERE photo_id = ? AND user_id = ?').run(photoId, userId);
      return res.changes > 0;
    },

    // Weeks
    weekData(circleId, weekId) {
      const photos = q(`${PHOTO_SELECT} WHERE p.circle_id = ? AND p.week_id = ? ORDER BY p.created_at`).all(circleId, weekId).map(photoRow);
      const reactions = q(
        `SELECT r.photo_id AS photoId, r.user_id AS userId, r.kind FROM reactions r
         JOIN photos p ON p.id = r.photo_id WHERE p.circle_id = ? AND p.week_id = ?`,
      ).all(circleId, weekId);
      const stars = q(
        `SELECT s.photo_id AS photoId, s.user_id AS userId, s.value FROM stars s
         JOIN photos p ON p.id = s.photo_id WHERE p.circle_id = ? AND p.week_id = ?`,
      ).all(circleId, weekId);
      return { photos, reactions, stars };
    },
    unclosedWeeksBefore: (weekId) =>
      q(
        `SELECT DISTINCT p.circle_id AS circleId, p.week_id AS weekId FROM photos p
         WHERE p.week_id < ? AND NOT EXISTS (SELECT 1 FROM weeks w WHERE w.circle_id = p.circle_id AND w.week_id = p.week_id)
         ORDER BY p.week_id`,
      ).all(weekId),
    circlesWithPhotosIn: (weekId) => q('SELECT DISTINCT circle_id AS circleId FROM photos WHERE week_id = ?').all(weekId).map((r) => r.circleId),
    unratedCounts(circleId, weekId) {
      return q(
        `SELECT u.id AS userId, COUNT(p.id) AS unrated FROM users u
         JOIN photos p ON p.circle_id = u.circle_id AND p.week_id = ? AND p.author_id <> u.id
         WHERE u.circle_id = ?
           AND NOT EXISTS (SELECT 1 FROM reactions r WHERE r.photo_id = p.id AND r.user_id = u.id)
           AND NOT EXISTS (SELECT 1 FROM stars s WHERE s.photo_id = p.id AND s.user_id = u.id)
         GROUP BY u.id`,
      ).all(weekId, circleId);
    },
    saveWeek: (circleId, weekId, closedAt, results) =>
      q('INSERT OR IGNORE INTO weeks (circle_id, week_id, closed_at, results) VALUES (?, ?, ?, ?)').run(circleId, weekId, closedAt, JSON.stringify(results))
        .changes > 0,
    closedWeeks: (circleId, limit) =>
      q('SELECT results FROM weeks WHERE circle_id = ? ORDER BY week_id DESC LIMIT ?').all(circleId, limit).map((r) => JSON.parse(r.results)),
    closedWeek(circleId, weekId) {
      const row = q('SELECT results FROM weeks WHERE circle_id = ? AND week_id = ?').get(circleId, weekId);
      return row ? JSON.parse(row.results) : null;
    },

    // One-off jobs (reminders) so a restart doesn't send them twice
    claimJob: (key, now) => q('INSERT OR IGNORE INTO jobs (key, done_at) VALUES (?, ?)').run(key, now).changes > 0,
  };
}
