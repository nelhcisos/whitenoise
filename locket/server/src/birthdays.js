// Birthdays: only the day and the month, never the year.

const MONTHS_GENITIVE = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
const DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const DAY_MS = 86_400_000;

/** Friends hear about a birthday this many days before it: a month (time for a parcel to arrive), 5 days, and on the day. */
export const BIRTHDAY_NOTICES = [30, 5, 0];

export const isValidBirthday = (month, day) =>
  Number.isInteger(month) && Number.isInteger(day) && month >= 1 && month <= 12 && day >= 1 && day <= DAYS_IN_MONTH[month - 1];

/** "11-14": how the API sends a birthday. */
export const birthdayKey = (month, day) => `${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;

/** "14 ноября", with the number kept next to its month. */
export const birthdayTitle = (month, day) => `${day} ${MONTHS_GENITIVE[month - 1]}`;

const isLeap = (year) => (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;

/**
 * Days from `today` ("2026-10-25", the friends' local date) to the next birthday;
 * 0 on the day. In other years 29 February is celebrated on the 28th.
 */
export function daysUntilBirthday(today, month, day) {
  const [y, m, d] = today.split('-').map(Number);
  const start = Date.UTC(y, m - 1, d);
  for (const year of [y, y + 1]) {
    const date = Date.UTC(year, month - 1, month === 2 && day === 29 && !isLeap(year) ? 28 : day);
    if (date >= start) return Math.round((date - start) / DAY_MS);
  }
  return null;
}
