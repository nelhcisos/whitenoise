import assert from 'node:assert/strict';
import { test } from 'node:test';
import { makeWeekCalendar } from '../src/week.js';

const moscow = makeWeekCalendar({ tzOffsetMinutes: 180, endDay: 7, endHour: 21 });
// Moscow is UTC+3, so 21:00 MSK = 18:00 UTC.

test('week flips on Sunday 21:00 local time', () => {
  assert.equal(moscow.weekIdFor(Date.UTC(2026, 9, 12, -3)), '2026-W42'); // Mon 00:00 MSK
  assert.equal(moscow.weekIdFor(Date.UTC(2026, 9, 14, 9)), '2026-W42'); // Wed
  assert.equal(moscow.weekIdFor(Date.UTC(2026, 9, 18, 18) - 1), '2026-W42'); // Sun 20:59:59.999
  assert.equal(moscow.weekIdFor(Date.UTC(2026, 9, 18, 18)), '2026-W43'); // Sun 21:00
});

test('week bounds match the flip moments', () => {
  assert.deepEqual(moscow.weekBounds('2026-W42'), {
    startsAt: Date.UTC(2026, 9, 11, 18),
    endsAt: Date.UTC(2026, 9, 18, 18),
  });
});

test('ISO year boundaries', () => {
  assert.equal(moscow.weekIdFor(Date.UTC(2026, 11, 31, 9)), '2026-W53');
  assert.equal(moscow.weekIdFor(Date.UTC(2027, 0, 3, 17)), '2026-W53'); // Sun 20:00 MSK
  assert.equal(moscow.weekIdFor(Date.UTC(2027, 0, 3, 18)), '2027-W01'); // Sun 21:00 MSK
  assert.equal(moscow.weekIdFor(Date.UTC(2021, 0, 1, 9)), '2020-W53');
});

test('plain ISO weeks when the week ends Monday 00:00 UTC', () => {
  const iso = makeWeekCalendar({ tzOffsetMinutes: 0, endDay: 1, endHour: 0 });
  assert.equal(iso.weekIdFor(Date.UTC(2026, 9, 14)), '2026-W42');
  assert.equal(iso.weekIdFor(Date.UTC(2026, 9, 12)), '2026-W42');
  assert.equal(iso.weekIdFor(Date.UTC(2026, 9, 12) - 1), '2026-W41');
  assert.deepEqual(iso.weekBounds('2026-W42'), { startsAt: Date.UTC(2026, 9, 12), endsAt: Date.UTC(2026, 9, 19) });
});

test('every moment lies inside the bounds of its own week', () => {
  const cal = makeWeekCalendar({ tzOffsetMinutes: -300, endDay: 6, endHour: 20 });
  for (let t = Date.UTC(2024, 0, 1); t < Date.UTC(2029, 0, 1); t += 3_600_000 * 7.3) {
    const { startsAt, endsAt } = cal.weekBounds(cal.weekIdFor(t));
    assert.ok(startsAt <= t && t < endsAt, new Date(t).toISOString());
    assert.equal(endsAt - startsAt, 7 * 24 * 3_600_000);
  }
});
