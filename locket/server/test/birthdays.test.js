import assert from 'node:assert/strict';
import test from 'node:test';
import { birthdayKey, birthdayTitle, daysUntilBirthday, isValidBirthday } from '../src/birthdays.js';

test('days until the next birthday, by the local date', () => {
  assert.equal(daysUntilBirthday('2026-11-14', 11, 14), 0);
  assert.equal(daysUntilBirthday('2026-11-13', 11, 14), 1);
  assert.equal(daysUntilBirthday('2026-10-15', 11, 14), 30);
  assert.equal(daysUntilBirthday('2026-11-15', 11, 14), 364, 'just passed: next year');
  assert.equal(daysUntilBirthday('2026-12-31', 1, 1), 1, 'across the new year');
  // 29 February: on the 28th in other years, on the 29th in leap years.
  assert.equal(daysUntilBirthday('2026-02-28', 2, 29), 0);
  assert.equal(daysUntilBirthday('2027-03-01', 2, 29), 365, 'next one is 29.02.2028');
  assert.equal(daysUntilBirthday('2028-02-28', 2, 29), 1);
});

test('only real days of a year are birthdays', () => {
  assert.ok(isValidBirthday(2, 29));
  assert.ok(isValidBirthday(12, 31));
  for (const [month, day] of [[2, 30], [4, 31], [13, 1], [0, 5], [5, 0], [1.5, 2], [Number.NaN, 1]]) {
    assert.ok(!isValidBirthday(month, day), `${month}/${day}`);
  }
  assert.equal(birthdayKey(3, 7), '03-07');
  assert.equal(birthdayTitle(11, 14), '14 ноября');
});
