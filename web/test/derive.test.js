// node --test — run from web/: `node --test`
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  BEAUFORT_RAMP,
  HOUR_MS,
  MINUTE_MS,
  arrowRotation,
  beaufortStep,
  beaufortToken,
  chartAriaLabel,
  compassLabel,
  compassWord,
  dayFraction,
  formatHHMM,
  hero,
  heroAriaLabel,
  horizonLabel,
  nowIndex,
  peakChipText,
  relativeTimePhrase,
  runLabel,
  shortDay,
  sunMarkers,
  toForecast,
  trustLine,
  trustState,
  twilightStops,
  tzAbbrev,
  yDomainMax,
} from '../lib/derive.js';

const here = dirname(fileURLToPath(import.meta.url));
const payload = JSON.parse(readFileSync(join(here, '..', '..', 'fixtures', 'payload-reference.json'), 'utf8'));
const forecast = toForecast(payload);
const TZ = forecast.location.tz;
const NOW = new Date(forecast.start.getTime() + 0.5 * HOUR_MS); // 09:30 PDT, fresh

test('view model shape (IMPLEMENTATION_PLAN §0)', () => {
  assert.equal(forecast.hours.length, 45);
  assert.equal(forecast.run, 'HRRR 15Z');
  assert.equal(forecast.location.name, 'Port Townsend Bay');
  assert.equal(forecast.location.isDefault, true);
  assert.equal(TZ, 'America/Los_Angeles');
  assert.equal(forecast.horizon.getTime(), forecast.start.getTime() + 44 * HOUR_MS);
  assert.equal(formatHHMM(forecast.start, TZ), '09:00');
  assert.equal(shortDay(forecast.start, TZ), 'Wed');
  assert.equal(formatHHMM(forecast.horizon, TZ), '05:00');
  assert.equal(shortDay(forecast.horizon, TZ), 'Fri');
  // §4.2a adds temp (°C) / cloud (%) / precip (mm/h) per hour; null when absent.
  assert.deepEqual(forecast.hours[0], { kn: 3, gust: 4, dirFrom: 290, temp: 10, cloud: 10, precip: 0 });
  assert.equal(forecast.peakGust.kn, 25);
  assert.equal(formatHHMM(forecast.peakGust.at, TZ), '00:00');
  for (const h of forecast.hours) {
    assert.ok(Number.isInteger(h.kn) && Number.isInteger(h.gust) && Number.isInteger(h.dirFrom));
  }
});

test('HANDOFF §10 expected values: hour 0', () => {
  const h = forecast.hours[0];
  assert.equal(`${h.kn} kn G${h.gust} from ${compassLabel(h.dirFrom)}`, '3 kn G4 from W');
  assert.equal(beaufortStep(h.kn), 1);
  assert.equal(beaufortToken(beaufortStep(h.kn)), 'calm');
  assert.equal(arrowRotation(h.dirFrom), 110);
});

test('HANDOFF §10 expected values: hour 15', () => {
  const h = forecast.hours[15];
  assert.equal(`${h.kn} kn G${h.gust} from ${compassLabel(h.dirFrom)}`, '15 kn G25 from W');
  assert.equal(beaufortStep(h.kn), 4);
  assert.equal(arrowRotation(h.dirFrom), 103);
});

test('Y domain max is 30 for the reference payload', () => {
  assert.equal(yDomainMax(forecast.hours), 30);
  assert.equal(yDomainMax([{ gust: 5 }]), 20);
  assert.equal(yDomainMax([{ gust: 17 }]), 20);
  assert.equal(yDomainMax([{ gust: 18 }]), 30);
  assert.equal(yDomainMax([{ gust: 47 }]), 50);
});

test('run label and horizon label', () => {
  assert.equal(runLabel(payload.run.latest), 'HRRR 15Z');
  assert.equal(runLabel(0), 'HRRR 00Z');
  assert.equal(horizonLabel(forecast), 'ends Fri 5am');
});

test('Beaufort table boundaries (HANDOFF §2)', () => {
  const expect = [
    [0, 0], [1, 1], [3, 1], [4, 2], [6, 2], [7, 3], [10, 3], [11, 4], [16, 4], [17, 5], [21, 5],
    [22, 6], [27, 6], [28, 7], [33, 7], [34, 8], [40, 8], [41, 9], [47, 9], [48, 10], [56, 11], [64, 12],
  ];
  for (const [kn, step] of expect) assert.equal(beaufortStep(kn), step, `kn ${kn}`);
  assert.equal(beaufortToken(0), 'calm');
  assert.equal(beaufortToken(1), 'calm');
  assert.equal(beaufortToken(10), '10');
  assert.equal(beaufortToken(12), '10');
  assert.equal(beaufortToken(7), '7');
});

test('compass label is 8-point with 22.5° half-sectors', () => {
  assert.equal(compassLabel(0), 'N');
  assert.equal(compassLabel(22), 'N');
  assert.equal(compassLabel(23), 'NE');
  assert.equal(compassLabel(90), 'E');
  assert.equal(compassLabel(180), 'S');
  assert.equal(compassLabel(270), 'W');
  assert.equal(compassLabel(337), 'NW');
  assert.equal(compassLabel(338), 'N');
  assert.equal(compassLabel(359), 'N');
  assert.equal(compassWord(290), 'west');
  assert.equal(arrowRotation(270), 90);
  assert.equal(arrowRotation(0), 180);
});

test('twilight stops match HANDOFF §6.2 within ±0.002', () => {
  const stops = twilightStops(forecast);
  assert.equal(stops[0].offset, 0);
  assert.equal(stops[0].value, 1, 'chart starts in day');
  assert.equal(stops[stops.length - 1].offset, 1);
  assert.equal(stops[stops.length - 1].value, 0, 'chart ends in night');
  const expected = [
    [0.2044, 1], // sunset Wed
    [0.2163, 0], // civil dusk Wed
    [0.4918, 0], // civil dawn Thu
    [0.5037, 1], // sunrise Thu
    [0.7370, 1], // sunset Thu
    [0.7489, 0], // civil dusk Thu
  ];
  const inner = stops.slice(1, -1);
  assert.equal(inner.length, expected.length, 'exactly six interior stops; Fri dawn is not emitted');
  inner.forEach((s, i) => {
    assert.ok(Math.abs(s.offset - expected[i][0]) <= 0.002, `stop ${i}: ${s.offset} vs ${expected[i][0]}`);
    assert.equal(s.value, expected[i][1], `stop ${i} value`);
  });
  for (const s of stops) assert.ok(s.offset >= 0 && s.offset <= 1);
  for (let i = 1; i < stops.length; i++) assert.ok(stops[i].offset >= stops[i - 1].offset, 'stops are sorted');
});

test('dayFraction ramps linearly across dawn→rise and set→dusk', () => {
  const d = forecast.sun[0];
  const mid = new Date((d.dawn.getTime() + d.rise.getTime()) / 2);
  assert.ok(Math.abs(dayFraction(mid, forecast.sun) - 0.5) < 1e-9);
  const q = new Date(d.set.getTime() + (d.dusk.getTime() - d.set.getTime()) * 0.25);
  assert.ok(Math.abs(dayFraction(q, forecast.sun) - 0.75) < 1e-9);
  assert.equal(dayFraction(new Date(d.rise.getTime() + HOUR_MS), forecast.sun), 1);
  assert.equal(dayFraction(new Date(d.dusk.getTime() + HOUR_MS), forecast.sun), 0);
});

test('sun dots only at sunrise and sunset inside the range', () => {
  const dots = sunMarkers(forecast);
  assert.deepEqual(dots.map((s) => s.kind), ['set', 'rise', 'set']);
  assert.ok(Math.abs(dots[0].offset - 0.2044) <= 0.002);
  assert.ok(Math.abs(dots[1].offset - 0.5037) <= 0.002);
  assert.ok(Math.abs(dots[2].offset - 0.7370) <= 0.002);
});

test('trust state tiers flip at 90 min and 6 h', () => {
  const at = (ms) => trustState({ forecast, now: new Date(forecast.fetched.getTime() + ms) }).kind;
  assert.equal(at(0), 'fresh');
  assert.equal(at(89 * MINUTE_MS), 'fresh');
  assert.equal(at(90 * MINUTE_MS), 'stale');
  assert.equal(at(6 * HOUR_MS - 1), 'stale');
  assert.equal(at(6 * HOUR_MS), 'old');
  assert.equal(trustState({ forecast: null, now: NOW }).kind, 'firstrun');
});

test('past horizon begins one hour after the last forecast hour', () => {
  const edge = forecast.horizon.getTime() + HOUR_MS;
  assert.equal(trustState({ forecast, now: new Date(edge - 1) }).kind, 'old');
  assert.equal(trustState({ forecast, now: new Date(edge) }).kind, 'horizon');
  assert.equal(hero(forecast, new Date(edge)), null);
  assert.equal(hero(forecast, new Date(edge - 1)).index, 44);
  // offline keeps the age tier; horizon wins over offline
  const off = trustState({ forecast, now: new Date(forecast.fetched.getTime() + 7 * HOUR_MS), lastCheckOK: false });
  assert.equal(off.kind, 'offline');
  assert.equal(off.tier, 'old');
  assert.equal(trustState({ forecast, now: new Date(edge), lastCheckOK: false }).kind, 'horizon');
  assert.equal(trustState({ forecast, now: NOW, updating: true }).kind, 'updating');
});

test('hero clamps to hour 0 before start and reads the current hour after', () => {
  assert.equal(hero(forecast, new Date(forecast.start.getTime() - HOUR_MS)).index, 0);
  assert.equal(hero(forecast, NOW).index, 0);
  assert.equal(hero(forecast, new Date(forecast.start.getTime() + 15.9 * HOUR_MS)).index, 15);
});

test('trust line text per HANDOFF §3', () => {
  const line = (ms, extra = {}) => {
    const now = new Date(forecast.fetched.getTime() + ms);
    return trustLine(forecast, trustState({ forecast, now, ...extra }), TZ);
  };
  assert.deepEqual(line(30 * MINUTE_MS), { text: 'as of 09:00 PDT · HRRR 15Z · forecast ends Fri 5am', amber: false, glyph: null });
  assert.deepEqual(line(2 * HOUR_MS), { text: 'as of 09:00 PDT · HRRR 15Z · forecast ends Fri 5am', amber: true, glyph: null });
  assert.deepEqual(line(7 * HOUR_MS), { text: 'as of Wed 09:00 PDT · HRRR 15Z · forecast ends Fri 5am', amber: true, glyph: null });
  // under 600 px the phrase is "ends Fri 5am"
  const compact = trustLine(forecast, trustState({ forecast, now: NOW }), TZ, { compact: true });
  assert.equal(compact.text, 'as of 09:00 PDT · HRRR 15Z · ends Fri 5am');
  assert.deepEqual(line(30 * MINUTE_MS, { lastCheckOK: false }), {
    text: "Couldn't reach server · showing data from 09:00", amber: true, glyph: 'wifi-slash',
  });
  assert.deepEqual(line(7 * HOUR_MS, { lastCheckOK: false }), {
    text: "Couldn't reach server · showing data from Wed 09:00", amber: true, glyph: 'wifi-slash',
  });
  assert.deepEqual(line(46 * HOUR_MS), { text: 'No forecast · last run HRRR 15Z Wed', amber: true, glyph: null });
  assert.deepEqual(line(30 * MINUTE_MS, { updating: true }), { text: 'updating · as of 09:00', amber: false, glyph: 'ring' });
  assert.equal(trustLine(null, trustState({ forecast: null, now: NOW }), TZ).text, 'No data yet. Needs cellular or Wi-Fi once.');
});

test('relative time phrase for the peak-gust chip', () => {
  const at = forecast.peakGust.at; // Thu 00:00 PDT
  assert.equal(relativeTimePhrase(at, NOW, TZ), 'around midnight');
  assert.equal(peakChipText(forecast, NOW), '25 kn gusts around midnight');
  const t = (hoursFromStart) => new Date(forecast.start.getTime() + hoursFromStart * HOUR_MS);
  assert.equal(relativeTimePhrase(t(1), NOW, TZ), 'this morning'); // 10:00 Wed
  assert.equal(relativeTimePhrase(t(5), NOW, TZ), 'this afternoon'); // 14:00
  assert.equal(relativeTimePhrase(t(9), NOW, TZ), 'this evening'); // 18:00
  assert.equal(relativeTimePhrase(t(13), NOW, TZ), 'around midnight'); // 22:00
  assert.equal(relativeTimePhrase(t(18), NOW, TZ), 'overnight'); // 03:00 Thu
  assert.equal(relativeTimePhrase(t(23), NOW, TZ), 'tomorrow morning'); // 08:00 Thu
  assert.equal(relativeTimePhrase(t(30), NOW, TZ), 'tomorrow afternoon'); // 15:00 Thu
  assert.equal(relativeTimePhrase(t(39), NOW, TZ), 'tomorrow night'); // 00:00 Fri
  assert.equal(relativeTimePhrase(t(0), NOW, TZ), 'now');
  assert.equal(relativeTimePhrase(t(15), t(16.5), TZ), 'around midnight'); // just past
  assert.equal(relativeTimePhrase(t(1), t(4), TZ), 'earlier this morning');
  assert.equal(relativeTimePhrase(t(15), t(30), TZ), 'last night');
  assert.equal(relativeTimePhrase(t(47), t(23), TZ), 'tomorrow morning'); // Fri 08:00 seen from Thu
  assert.equal(relativeTimePhrase(t(47), NOW, TZ), 'Fri morning'); // Fri 08:00 seen from Wed
});

test('accessibility labels (HANDOFF §11)', () => {
  assert.equal(chartAriaLabel(forecast), '45-hour wind chart: sustained 2 to 15 knots, gusts to 25 knots, ends Friday 05:00');
  assert.equal(heroAriaLabel(forecast.hours[15], new Date(Date.UTC(2026, 9, 22, 6, 30)), TZ), '15 knots, gusting 25, from the west, as of 23:30');
  assert.equal(heroAriaLabel(hero(forecast, NOW), forecast.fetched, TZ), '3 knots, gusting 4, from the west, as of 09:00');
});

test('time zone comes from the payload, not the machine', () => {
  assert.equal(tzAbbrev(forecast.start, TZ), 'PDT');
  assert.equal(formatHHMM(forecast.start, 'UTC'), '16:00');
  assert.equal(formatHHMM(forecast.start, 'Europe/London'), '17:00');
  assert.equal(shortDay(forecast.horizon, 'Asia/Tokyo'), 'Fri');
});

test('styles.css carries the exact Beaufort ramp hexes from HANDOFF §4.1', () => {
  const css = readFileSync(join(here, '..', 'styles.css'), 'utf8');
  for (const [token, v] of Object.entries(BEAUFORT_RAMP)) {
    for (const scheme of ['dark', 'light']) {
      assert.ok(css.includes(v[scheme]), `bft.${token} ${scheme} ${v[scheme]} missing from styles.css`);
    }
  }
  assert.ok(css.includes('#B86E00'), 'light amber');
  assert.ok(css.includes('#FFB340'), 'dark amber');
});
