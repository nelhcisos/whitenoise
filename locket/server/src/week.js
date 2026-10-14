const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;

// Weeks are ISO weeks of a "virtual" clock: local time shifted so that the
// configured week end (e.g. Sunday 21:00) lands exactly on Monday 00:00.
// A photo posted Sunday 21:05 therefore already belongs to the next week.
export function makeWeekCalendar({ tzOffsetMinutes = 180, endDay = 7, endHour = 21 } = {}) {
  if (!(endDay >= 1 && endDay <= 7) || !(endHour >= 0 && endHour <= 23)) {
    throw new Error('WEEK_END_DAY must be 1..7 and WEEK_END_HOUR 0..23');
  }
  const shift = ((((7 - endDay) * 24 + (24 - endHour)) % 168) * HOUR);
  const offset = tzOffsetMinutes * 60_000;
  const toVirtual = (ms) => ms + offset + shift;
  const fromVirtual = (ms) => ms - offset - shift;

  function weekIdFor(ms) {
    const d = new Date(toVirtual(ms));
    const weekday = (d.getUTCDay() + 6) % 7; // Monday = 0
    const thursday = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - weekday + 3);
    const year = new Date(thursday).getUTCFullYear();
    const week = Math.floor((thursday - firstMonday(year)) / WEEK) + 1;
    return `${year}-W${String(week).padStart(2, '0')}`;
  }

  function weekBounds(weekId) {
    const m = /^(\d{4})-W(\d{2})$/.exec(weekId);
    if (!m) throw new Error(`Bad week id ${weekId}`);
    const monday = firstMonday(Number(m[1])) + (Number(m[2]) - 1) * WEEK;
    return { startsAt: fromVirtual(monday), endsAt: fromVirtual(monday + WEEK) };
  }

  return { weekIdFor, weekBounds };
}

// Monday of ISO week 1 (the week containing January 4th), as a UTC timestamp.
function firstMonday(year) {
  const jan4 = Date.UTC(year, 0, 4);
  const weekday = (new Date(jan4).getUTCDay() + 6) % 7;
  return jan4 - weekday * DAY;
}
