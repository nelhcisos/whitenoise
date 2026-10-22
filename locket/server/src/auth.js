import crypto from 'node:crypto';

/**
 * The account key. A password IS the account (API.md «Модель»), so it is looked
 * up, not verified: HMAC with a server-side pepper keeps a leaked database
 * useless without the pepper file.
 */
export function passwordKey(pepper, password) {
  return crypto.createHmac('sha256', pepper).update(String(password).normalize('NFC'), 'utf8').digest('hex');
}

export function newSessionToken() {
  const token = crypto.randomBytes(32).toString('base64url');
  return { token, hash: hashToken(token) };
}

export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// Small in-memory brake: at most `max` hits per key (client IP) per window.
// The window starts at the first hit.
export function createAttemptLimiter({ max = 10, windowMs = 15 * 60_000 } = {}) {
  const hits = new Map();
  return {
    blocked(key, now) {
      const h = hits.get(key);
      return Boolean(h && h.resetAt > now && h.count >= max);
    },
    fail(key, now) {
      const h = hits.get(key);
      if (!h || h.resetAt <= now) hits.set(key, { count: 1, resetAt: now + windowMs });
      else h.count++;
      if (hits.size > 10_000) for (const [k, v] of hits) if (v.resetAt <= now) hits.delete(k);
    },
    reset(key) {
      hits.delete(key);
    },
  };
}
