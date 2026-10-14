import crypto from 'node:crypto';
import { promisify } from 'node:util';

const scrypt = promisify(crypto.scrypt);

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = await scrypt(password, salt, 64);
  return `scrypt$${salt.toString('hex')}$${hash.toString('hex')}`;
}

export async function verifyPassword(password, stored) {
  const [scheme, saltHex, hashHex] = String(stored).split('$');
  if (scheme !== 'scrypt' || !saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = await scrypt(password, Buffer.from(saltHex, 'hex'), expected.length);
  return crypto.timingSafeEqual(expected, actual);
}

export function newSessionToken() {
  const token = crypto.randomBytes(32).toString('base64url');
  return { token, hash: hashToken(token) };
}

export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// Small in-memory brake on password guessing: N failures per key per window.
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
