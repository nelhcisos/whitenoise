import crypto from 'node:crypto';

// Usernames are picked, never typed: the server offers one of each kind.
// These lists are placeholders — swap in the generated ones later. Rules for
// any list: lowercase Cyrillic, no spaces or digits, no slurs against groups.
export const USERNAME_WORDS = {
  animal: [
    'барсук', 'ёжик', 'енот', 'лиса', 'сова', 'бобр', 'выдра', 'хорёк', 'лось', 'кабан',
    'рысь', 'тюлень', 'пингвин', 'капибара', 'хомяк', 'суслик', 'крот', 'белка', 'волк', 'медведь',
    'жаба', 'утка', 'гусь', 'козёл', 'баран', 'ленивец', 'тушканчик', 'опоссум', 'морж', 'кальмар',
  ],
  swear: [
    'хуй', 'хуйло', 'хуепутало', 'хуеплёт', 'пиздец', 'пиздюк', 'пиздабол', 'ебанат', 'ебланчик', 'ебака',
    'мудак', 'мудила', 'мудозвон', 'залупа', 'долбоёб', 'уёбок', 'блядун', 'жопа', 'говнюк', 'засранец',
    'херня', 'сучара',
  ],
  name: [
    'ярослав', 'ярослава', 'святослав', 'мирослава', 'богдан', 'богдана', 'всеволод', 'людмила', 'ратибор', 'радмила',
    'добрыня', 'забава', 'ростислав', 'любава', 'велеслав', 'милослава', 'ждан', 'злата', 'тихомир', 'владислава',
    'мстислав', 'ведана', 'остромир', 'снежана',
  ],
};

export const USERNAME_KINDS = Object.keys(USERNAME_WORDS);

/** Lowercase, "ё" → "е": "Ёжик" and "ежик" are the same username. */
export function usernameKey(value) {
  return String(value ?? '').trim().toLowerCase().replace(/ё/g, 'е');
}

const BASE_KEYS = new Set(USERNAME_KINDS.flatMap((kind) => USERNAME_WORDS[kind].map(usernameKey)));
const GRAMMAR = /^(\D+?)([2-9]|[1-9]\d{1,2})?$/u;

/**
 * Whether a username could have come from the generator: a word from any list,
 * then nothing or a number 2–999. Clients can't invent their own.
 * Returns the canonical spelling (the list word with its "ё") or null.
 */
export function canonicalUsername(value) {
  const key = usernameKey(value);
  const match = GRAMMAR.exec(key);
  if (!match || !BASE_KEYS.has(match[1])) return null;
  const word = USERNAME_KINDS.flatMap((kind) => USERNAME_WORDS[kind]).find((w) => usernameKey(w) === match[1]);
  return word + (match[2] ?? '');
}

const pick = (list) => list[crypto.randomInt(list.length)];

/**
 * One free username of the given kind. `isTaken(key)` checks the database.
 * The bare word first, then the word with 2–99 (20 tries), then 100–999.
 */
export function suggestUsername(kind, isTaken) {
  const words = USERNAME_WORDS[kind];
  for (let attempt = 0; attempt < 5; attempt++) {
    const word = pick(words);
    if (!isTaken(usernameKey(word))) return word;
  }
  for (const [min, max, tries] of [[2, 100, 20], [100, 1000, 50]]) {
    for (let i = 0; i < tries; i++) {
      const candidate = `${pick(words)}${crypto.randomInt(min, max)}`;
      if (!isTaken(usernameKey(candidate))) return candidate;
    }
  }
  throw new Error(`no free username left for kind ${kind}`);
}

/** Three suggestions, one of each kind, all free right now and all different. */
export function suggestUsernames(isTaken) {
  const offered = new Set();
  return USERNAME_KINDS.map((kind) => {
    const username = suggestUsername(kind, (key) => offered.has(key) || isTaken(key));
    offered.add(usernameKey(username));
    return { username, kind };
  });
}
