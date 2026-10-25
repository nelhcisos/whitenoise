import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export const SCHEMA_VERSION = 3;

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT,
  username_key TEXT UNIQUE,
  password_key TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL
);
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
CREATE TABLE IF NOT EXISTS friend_requests (
  from_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (from_id, to_id)
);
CREATE INDEX IF NOT EXISTS friend_requests_to ON friend_requests(to_id);
CREATE TABLE IF NOT EXISTS friendships (
  user_a TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_b TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b)
);
CREATE INDEX IF NOT EXISTS friendships_b ON friendships(user_b);
CREATE TABLE IF NOT EXISTS photos (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_id TEXT NOT NULL,
  caption TEXT,
  file TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS photos_author_week ON photos(author_id, week_id, created_at);
CREATE INDEX IF NOT EXISTS photos_created ON photos(created_at);
CREATE INDEX IF NOT EXISTS photos_week ON photos(week_id);
CREATE TABLE IF NOT EXISTS reactions (
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('creative', 'funny', 'wild')),
  created_at INTEGER NOT NULL,
  PRIMARY KEY (photo_id, user_id, kind)
);
CREATE INDEX IF NOT EXISTS reactions_user ON reactions(user_id);
CREATE TABLE IF NOT EXISTS stars (
  photo_id TEXT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  value INTEGER NOT NULL CHECK (value BETWEEN 1 AND 3),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (photo_id, user_id)
);
CREATE INDEX IF NOT EXISTS stars_user ON stars(user_id);
CREATE TABLE IF NOT EXISTS weeks (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_id TEXT NOT NULL,
  closed_at INTEGER NOT NULL,
  results TEXT NOT NULL,
  PRIMARY KEY (user_id, week_id)
);
CREATE TABLE IF NOT EXISTS days (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 5),
  reasons TEXT NOT NULL,
  liked TEXT NOT NULL,
  condition INTEGER,
  place INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, date)
);
CREATE TABLE IF NOT EXISTS duels (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  left_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  right_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  send_at INTEGER NOT NULL,
  sent_at INTEGER,
  choice TEXT CHECK (choice IN ('left', 'right')),
  chosen_id TEXT,
  week_id TEXT,
  chosen_at INTEGER,
  UNIQUE (user_id, date)
);
CREATE INDEX IF NOT EXISTS duels_due ON duels(sent_at, send_at);
CREATE INDEX IF NOT EXISTS duels_week ON duels(week_id, chosen_id);
CREATE TABLE IF NOT EXISTS wishes (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  url TEXT,
  file TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS wishes_user ON wishes(user_id, created_at);
CREATE TABLE IF NOT EXISTS jobs (
  key TEXT PRIMARY KEY,
  done_at INTEGER NOT NULL
);
`;

/**
 * Opens (or creates) the database. Version 2 → 3 only adds tables (wishes), which
 * CREATE TABLE IF NOT EXISTS does in place. A version 1 file — companies, email sign-in —
 * is moved aside as locket.v1-<time>.db and a fresh one is created next to it:
 * nothing is deleted, but the old data is not carried over.
 */
export function openDb(file, { log = console, stamp = () => new Date().toISOString().replace(/[:.]/g, '-') } = {}) {
  if (file !== ':memory:' && fs.existsSync(file)) moveAsideIfV1(file, log, stamp);
  const db = new DatabaseSync(file);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  db.exec(SCHEMA);
  db.exec(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  return db;
}

function moveAsideIfV1(file, log, stamp) {
  const probe = new DatabaseSync(file);
  let isV1;
  try {
    const version = probe.prepare('PRAGMA user_version').get().user_version;
    const circles = probe.prepare("SELECT 1 AS x FROM sqlite_master WHERE type = 'table' AND name = 'circles'").get();
    isV1 = version < SCHEMA_VERSION && Boolean(circles);
  } finally {
    probe.close();
  }
  if (!isV1) return;
  const backup = path.join(path.dirname(file), `locket.v1-${stamp()}.db`);
  fs.renameSync(file, backup);
  for (const ext of ['-wal', '-shm']) {
    if (fs.existsSync(file + ext)) fs.renameSync(file + ext, backup + ext);
  }
  log.warn(`Old database (companies + email) moved to ${backup}; starting a fresh one.`);
}

const boolToInt = (value) => (value === null || value === undefined ? null : value ? 1 : 0);
const intToBool = (value) => (value === null || value === undefined ? null : value === 1);
const DUEL_SELECT = `SELECT d.*, l.username AS left_name, r.username AS right_name FROM duels d
  JOIN users l ON l.id = d.left_id JOIN users r ON r.id = d.right_id`;
const duelRow = (r) =>
  r && {
    id: r.id,
    userId: r.user_id,
    date: r.date,
    left: { id: r.left_id, username: r.left_name },
    right: { id: r.right_id, username: r.right_name },
    sendAt: r.send_at,
    sentAt: r.sent_at,
    choice: r.choice,
  };
const dayRow = (r) =>
  r && {
    date: r.date,
    stars: r.stars,
    reasons: JSON.parse(r.reasons),
    liked: JSON.parse(r.liked),
    condition: intToBool(r.condition),
    place: intToBool(r.place),
    updatedAt: r.updated_at,
  };

export function createStore(db) {
  const q = (sql) => db.prepare(sql);
  const placeholders = (n) => Array(n).fill('?').join(',');

  const photoRow = (r) =>
    r && {
      id: r.id,
      rowid: r.rid,
      authorId: r.author_id,
      authorName: r.author_name,
      weekId: r.week_id,
      caption: r.caption,
      file: r.file,
      createdAt: r.created_at,
    };
  const userRow = (r) => r && { id: r.id, username: r.username, usernameKey: r.username_key };
  const PHOTO_SELECT = 'SELECT p.rowid AS rid, p.*, u.username AS author_name FROM photos p JOIN users u ON u.id = p.author_id';
  // The other side of a friendship row, for a given user.
  const FRIEND_IDS = 'SELECT CASE WHEN user_a = ?1 THEN user_b ELSE user_a END AS id, created_at FROM friendships WHERE user_a = ?1 OR user_b = ?1';
  const pair = (a, b) => (a < b ? [a, b] : [b, a]);

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

    // ---------- users & sessions ----------
    createUser: ({ id, passwordKey, now }) =>
      q('INSERT INTO users (id, password_key, created_at) VALUES (?, ?, ?)').run(id, passwordKey, now),
    user: (id) => userRow(q('SELECT * FROM users WHERE id = ?').get(id)),
    userByPasswordKey: (key) => userRow(q('SELECT * FROM users WHERE password_key = ?').get(key)),
    usernameTaken: (key) => Boolean(q('SELECT 1 AS x FROM users WHERE username_key = ?').get(key)),
    // Only once: a chosen username never changes. Returns true when it was set.
    setUsername: (id, username, key) =>
      q('UPDATE users SET username = ?, username_key = ? WHERE id = ? AND username IS NULL').run(username, key, id).changes > 0,
    usersWithUsername: () => q('SELECT * FROM users WHERE username IS NOT NULL ORDER BY username_key').all().map(userRow),
    usersByIds(ids) {
      if (!ids.length) return [];
      return q(`SELECT * FROM users WHERE id IN (${placeholders(ids.length)}) ORDER BY username_key`).all(...ids).map(userRow);
    },
    // Prefix search on the normalised key; an exact match comes first.
    searchUsers(prefix, limit) {
      const like = `${prefix.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
      return q(
        `SELECT * FROM users WHERE username_key LIKE ? ESCAPE '\\'
         ORDER BY (username_key = ?) DESC, username_key LIMIT ?`,
      ).all(like, prefix, limit).map(userRow);
    },

    createSession: (tokenHash, userId, now) =>
      q('INSERT INTO sessions (token_hash, user_id, created_at) VALUES (?, ?, ?)').run(tokenHash, userId, now),
    userBySession: (tokenHash) =>
      userRow(q('SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?').get(tokenHash)),
    deleteSession: (tokenHash) => q('DELETE FROM sessions WHERE token_hash = ?').run(tokenHash),

    // ---------- devices (APNs tokens) ----------
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

    // ---------- friends ----------
    friendIds: (userId) => q(FRIEND_IDS).all(userId).map((r) => r.id),
    friends: (userId) =>
      q(
        `SELECT u.id, u.username, f.created_at AS since,
           (SELECT COUNT(*) FROM wishes w WHERE w.user_id = u.id) AS wishCount
         FROM (${FRIEND_IDS}) f JOIN users u ON u.id = f.id ORDER BY u.username_key`,
      ).all(userId),
    friendCount: (userId) => q('SELECT COUNT(*) AS n FROM friendships WHERE user_a = ?1 OR user_b = ?1').get(userId).n,
    areFriends: (a, b) => Boolean(q('SELECT 1 AS x FROM friendships WHERE user_a = ? AND user_b = ?').get(...pair(a, b))),
    addFriendship: (a, b, now) =>
      q('INSERT OR IGNORE INTO friendships (user_a, user_b, created_at) VALUES (?, ?, ?)').run(...pair(a, b), now),
    removeFriendship: (a, b) => q('DELETE FROM friendships WHERE user_a = ? AND user_b = ?').run(...pair(a, b)),

    hasRequest: (fromId, toId) => Boolean(q('SELECT 1 AS x FROM friend_requests WHERE from_id = ? AND to_id = ?').get(fromId, toId)),
    // Returns true when a new request was stored.
    createRequest: (fromId, toId, now) =>
      q('INSERT OR IGNORE INTO friend_requests (from_id, to_id, created_at) VALUES (?, ?, ?)').run(fromId, toId, now).changes > 0,
    deleteRequestsBetween: (a, b) =>
      q('DELETE FROM friend_requests WHERE (from_id = ?1 AND to_id = ?2) OR (from_id = ?2 AND to_id = ?1)').run(a, b),
    incoming: (userId) =>
      q(
        `SELECT u.id, u.username, r.created_at AS createdAt FROM friend_requests r JOIN users u ON u.id = r.from_id
         WHERE r.to_id = ? ORDER BY r.created_at DESC, r.rowid DESC`,
      ).all(userId),
    outgoing: (userId) =>
      q(
        `SELECT u.id, u.username, r.created_at AS createdAt FROM friend_requests r JOIN users u ON u.id = r.to_id
         WHERE r.from_id = ? ORDER BY r.created_at DESC, r.rowid DESC`,
      ).all(userId),
    incomingCount: (userId) => q('SELECT COUNT(*) AS n FROM friend_requests WHERE to_id = ?').get(userId).n,

    // ---------- photos ----------
    // ---------- wishes ----------
    wishes: (userId) =>
      q(
        `SELECT id, user_id AS userId, title, url, file, created_at AS createdAt FROM wishes
         WHERE user_id = ? ORDER BY created_at DESC, rowid DESC`,
      ).all(userId),
    wish: (id) => q('SELECT id, user_id AS userId, title, url, file, created_at AS createdAt FROM wishes WHERE id = ?').get(id),
    wishCount: (userId) => q('SELECT COUNT(*) AS n FROM wishes WHERE user_id = ?').get(userId).n,
    insertWish: ({ id, userId, title, url, file, now }) =>
      q('INSERT INTO wishes (id, user_id, title, url, file, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(id, userId, title, url, file, now),
    deleteWish: (id) => q('DELETE FROM wishes WHERE id = ?').run(id),

    insertPhoto: ({ id, authorId, weekId, caption, file, now }) =>
      q('INSERT INTO photos (id, author_id, week_id, caption, file, created_at) VALUES (?, ?, ?, ?, ?, ?)').run(
        id, authorId, weekId, caption, file, now,
      ),
    photo: (id) => photoRow(q(`${PHOTO_SELECT} WHERE p.id = ?`).get(id)),
    deletePhoto: (id) => q('DELETE FROM photos WHERE id = ?').run(id),
    feed(authorIds, before, limit) {
      if (!authorIds.length) return [];
      return q(
        `${PHOTO_SELECT} WHERE p.author_id IN (${placeholders(authorIds.length)}) AND p.created_at < ?
         ORDER BY p.created_at DESC, p.rowid DESC LIMIT ?`,
      ).all(...authorIds, before, limit).map(photoRow);
    },
    // How many photos the user posted in that week.
    postsInWeek: (userId, weekId) => q('SELECT COUNT(*) AS n FROM photos WHERE author_id = ? AND week_id = ?').get(userId, weekId).n,
    // The photo's place among its author's photos of that week, from 0, by (created_at, rowid).
    rankInWeek: (photo) =>
      q(
        `SELECT COUNT(*) AS n FROM photos WHERE author_id = ? AND week_id = ?
         AND (created_at < ? OR (created_at = ? AND rowid < ?))`,
      ).get(photo.authorId, photo.weekId, photo.createdAt, photo.createdAt, photo.rowid).n,
    // All photos of these authors in a week, oldest first per author (rank = position).
    photosByAuthorsInWeek(authorIds, weekId) {
      if (!authorIds.length) return [];
      return q(
        `${PHOTO_SELECT} WHERE p.week_id = ? AND p.author_id IN (${placeholders(authorIds.length)})
         ORDER BY p.author_id, p.created_at, p.rowid`,
      ).all(weekId, ...authorIds).map(photoRow);
    },
    // Photos the user has rated or reacted to, among the given ones.
    ratedBy(userId, photoIds) {
      if (!photoIds.length) return new Set();
      const ids = placeholders(photoIds.length);
      return new Set(
        q(
          `SELECT photo_id AS id FROM reactions WHERE user_id = ? AND photo_id IN (${ids})
           UNION SELECT photo_id AS id FROM stars WHERE user_id = ? AND photo_id IN (${ids})`,
        ).all(userId, ...photoIds, userId, ...photoIds).map((r) => r.id),
      );
    },

    // Ratings are blind: these two are the only per-photo ratings anyone is sent,
    // and only the viewer's own.
    myReactionsFor(photoIds, userId) {
      if (!photoIds.length) return [];
      return q(
        `SELECT photo_id AS photoId, kind FROM reactions
         WHERE user_id = ? AND photo_id IN (${placeholders(photoIds.length)}) ORDER BY created_at, rowid`,
      ).all(userId, ...photoIds);
    },
    // Returns true when the reaction state actually changed.
    setReaction(photoId, userId, kind, on, now) {
      const res = on
        ? q('INSERT OR IGNORE INTO reactions (photo_id, user_id, kind, created_at) VALUES (?, ?, ?, ?)').run(photoId, userId, kind, now)
        : q('DELETE FROM reactions WHERE photo_id = ? AND user_id = ? AND kind = ?').run(photoId, userId, kind);
      return res.changes > 0;
    },
    myStarsFor(photoIds, userId) {
      if (!photoIds.length) return [];
      return q(`SELECT photo_id AS photoId, value FROM stars WHERE user_id = ? AND photo_id IN (${placeholders(photoIds.length)})`).all(
        userId,
        ...photoIds,
      );
    },
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

    // ---------- weeks ----------
    /**
     * Everything a viewer's weekly results need: the week's photos posted by the
     * circle (viewer + friends), plus photos the circle rated (they only count
     * towards "given"), and every rating on those photos.
     */
    weekData(memberIds, weekId) {
      if (!memberIds.length) return { photos: [], reactions: [], stars: [] };
      const ids = placeholders(memberIds.length);
      const photos = q(
        `${PHOTO_SELECT} WHERE p.week_id = ? AND (
           p.author_id IN (${ids})
           OR EXISTS (SELECT 1 FROM reactions r WHERE r.photo_id = p.id AND r.user_id IN (${ids}))
           OR EXISTS (SELECT 1 FROM stars s WHERE s.photo_id = p.id AND s.user_id IN (${ids})))
         ORDER BY p.created_at, p.rowid`,
      ).all(weekId, ...memberIds, ...memberIds, ...memberIds).map(photoRow);
      const photoIds = photos.map((p) => p.id);
      if (!photoIds.length) return { photos, reactions: [], stars: [] };
      const pids = placeholders(photoIds.length);
      const reactions = q(`SELECT photo_id AS photoId, user_id AS userId, kind FROM reactions WHERE photo_id IN (${pids})`).all(...photoIds);
      const stars = q(`SELECT photo_id AS photoId, user_id AS userId, value FROM stars WHERE photo_id IN (${pids})`).all(...photoIds);
      return { photos, reactions, stars };
    },
    weeksWithPhotosBefore: (weekId) =>
      q('SELECT DISTINCT week_id AS weekId FROM photos WHERE week_id < ? ORDER BY week_id').all(weekId).map((r) => r.weekId),
    // Returns true when this snapshot is new.
    saveWeek: (userId, weekId, closedAt, results) =>
      q('INSERT OR IGNORE INTO weeks (user_id, week_id, closed_at, results) VALUES (?, ?, ?, ?)').run(userId, weekId, closedAt, JSON.stringify(results))
        .changes > 0,
    closedWeeks: (userId, limit) =>
      q('SELECT results FROM weeks WHERE user_id = ? ORDER BY week_id DESC LIMIT ?').all(userId, limit).map((r) => JSON.parse(r.results)),
    closedWeek(userId, weekId) {
      const row = q('SELECT results FROM weeks WHERE user_id = ? AND week_id = ?').get(userId, weekId);
      return row ? JSON.parse(row.results) : null;
    },

    // ---------- the day rating (private: only its owner reads it) ----------
    saveDay: ({ userId, date, stars, reasons, liked, condition, place, now }) =>
      q(
        `INSERT INTO days (user_id, date, stars, reasons, liked, condition, place, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(user_id, date) DO UPDATE SET stars = excluded.stars, reasons = excluded.reasons, liked = excluded.liked,
           condition = excluded.condition, place = excluded.place, updated_at = excluded.updated_at`,
      ).run(userId, date, stars, JSON.stringify(reasons), JSON.stringify(liked), boolToInt(condition), boolToInt(place), now),
    day: (userId, date) => dayRow(q('SELECT * FROM days WHERE user_id = ? AND date = ?').get(userId, date)),
    days: (userId, limit) => q('SELECT * FROM days WHERE user_id = ? ORDER BY date DESC LIMIT ?').all(userId, limit).map(dayRow),

    // ---------- «Кто лучше?»: one pick between two friends a day ----------
    createDuel: ({ id, userId, date, leftId, rightId, sendAt }) =>
      q('INSERT OR IGNORE INTO duels (id, user_id, date, left_id, right_id, send_at) VALUES (?, ?, ?, ?, ?, ?)').run(
        id, userId, date, leftId, rightId, sendAt,
      ),
    duel: (id) => duelRow(q(`${DUEL_SELECT} WHERE d.id = ?`).get(id)),
    duelFor: (userId, date) => duelRow(q(`${DUEL_SELECT} WHERE d.user_id = ? AND d.date = ?`).get(userId, date)),
    duelsDue: (now) => q(`${DUEL_SELECT} WHERE d.sent_at IS NULL AND d.send_at <= ? ORDER BY d.send_at`).all(now).map(duelRow),
    setDuelPair: (id, leftId, rightId) => q('UPDATE duels SET left_id = ?, right_id = ? WHERE id = ?').run(leftId, rightId, id),
    deleteDuel: (id) => q('DELETE FROM duels WHERE id = ?').run(id),
    markDuelSent: (id, now) => q('UPDATE duels SET sent_at = ? WHERE id = ?').run(now, id),
    // Only once: returns true when the pick was stored.
    chooseDuel: (id, choice, chosenId, weekId, now) =>
      q('UPDATE duels SET choice = ?, chosen_id = ?, week_id = ?, chosen_at = ? WHERE id = ? AND choice IS NULL').run(
        choice, chosenId, weekId, now, id,
      ).changes > 0,
    // The week's most picked person: most picks, then alphabetical. Nobody else's count leaves here.
    mostPickedInWeek: (weekId) =>
      q(
        `SELECT d.chosen_id AS userId, u.username AS name, COUNT(*) AS picks FROM duels d
         JOIN users u ON u.id = d.chosen_id
         WHERE d.week_id = ? GROUP BY d.chosen_id ORDER BY picks DESC, u.username_key LIMIT 1`,
      ).get(weekId),

    // ---------- one-off jobs (week closing, reminders) so a restart doesn't repeat them ----------
    claimJob: (key, now) => q('INSERT OR IGNORE INTO jobs (key, done_at) VALUES (?, ?)').run(key, now).changes > 0,
    jobDone: (key) => Boolean(q('SELECT 1 AS x FROM jobs WHERE key = ?').get(key)),
  };
}
