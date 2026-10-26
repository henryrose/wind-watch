// node --test — 26 Oct handoff: 48 h / 7 d ranges with NBM after the HRRR
// horizon (spec §12a, mixed_reference.py), the sky band and temperature
// (§12b, sky_reference.py), sunrise filled / sunset ring (§5).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  CHART_STYLES,
  HOUR_MS,
  MINUTE_MS,
  chartAriaLabel,
  chartLayout,
  chartSlots,
  conditionsParts,
  formatTemp,
  hourAtX,
  hrrrBlocks,
  parseRange,
  parseTempUnit,
  rainTicks,
  rainWord,
  rangeHint,
  rangePeak,
  rangeSpan,
  rangeTitle,
  selectionGeometry,
  skyCells,
  skyTone,
  skyWord,
  slotLabel,
  slotMode,
  slotTableLabel,
  spanText,
  tableCaption,
  tableRows,
  tempValue,
  toForecast,
  trustLine,
  trustState,
} from '../lib/derive.js';

const here = dirname(fileURLToPath(import.meta.url));
const payload = JSON.parse(readFileSync(join(here, '..', '..', 'fixtures', 'payload-reference.json'), 'utf8'));
const forecast = toForecast(payload);
const TZ = forecast.location.tz;
const NOW = new Date(forecast.start.getTime() + 0.4 * HOUR_MS);

// The same payload as the live server serves it today: no §4.2a fields.
const bare = { ...payload };
delete bare.temp;
delete bare.cloud;
delete bare.precip;
delete bare.extended;
const hrrrOnly = toForecast(bare);
const nbmNull = toForecast({ ...payload, extended: null });

const near = (a, b, msg, tol = 0.06) => assert.ok(Math.abs(a - b) <= tol, `${msg}: ${a} vs ${b}`);

test('extended → NBM blocks after the HRRR horizon (fixture: 33 blocks, hour 45 → 144, ends Tue 9am)', () => {
  const ext = forecast.extended;
  assert.equal(ext.model, 'NBM');
  assert.equal(ext.run, 'NBM 13Z');
  assert.equal(ext.fromIdx, 45, 'from == start + hours·3600');
  assert.equal(ext.blocks.length, 33);
  assert.equal(ext.blocks[0].t, 45);
  assert.equal(ext.blocks[32].t, 141);
  assert.equal(ext.end.getTime(), forecast.start.getTime() + 144 * HOUR_MS);
  assert.deepEqual(
    { kn: ext.blocks[10].kn, gust: ext.blocks[10].gust, dirFrom: ext.blocks[10].dirFrom },
    { kn: 18, gust: 32, dirFrom: 205 },
    'Sat 12–3pm block (hour 75) from mixed_reference.py',
  );
  assert.equal(ext.blocks[10].t, 75);
});

test('missing / null / malformed extended and missing sky fields never throw', () => {
  assert.equal(hrrrOnly.extended, null);
  assert.equal(nbmNull.extended, null);
  assert.equal(toForecast({ ...payload, extended: { ...payload.extended, kn: [1] } }).extended, null);
  assert.deepEqual(hrrrOnly.hours[0], { kn: 3, gust: 4, dirFrom: 290, temp: null, cloud: null, precip: null });
  // a short array counts as absent
  assert.equal(toForecast({ ...payload, temp: [1, 2] }).hours[0].temp, null);
  assert.deepEqual(skyCells(hrrrOnly, '48h'), []);
  assert.deepEqual(conditionsParts(hrrrOnly.hours[15]), []);
});

test('range parsing and spans: 48 h = HRRR; 7 d = HRRR then NBM; 7 d without NBM stops at the HRRR edge', () => {
  assert.equal(parseRange('7d'), '7d');
  assert.equal(parseRange('48h'), '48h');
  assert.equal(parseRange('10d'), null);
  assert.deepEqual({ ...rangeSpan(forecast, '48h'), end: null }, { range: '48h', total: 45, end: null, nbm: false });
  assert.equal(rangeSpan(forecast, '7d').total, 144);
  assert.equal(rangeSpan(forecast, '7d').nbm, true);
  assert.equal(rangeSpan(nbmNull, '7d').total, 45);
  assert.equal(rangeSpan(nbmNull, '7d').nbm, false);
});

test('slot rule: under 4 px per hour the whole chart goes 3-hourly', () => {
  assert.equal(slotMode(1120, 144), 'hourly'); // web desktop: 7.8 px/h
  assert.equal(slotMode(358, 144), '3-hourly'); // web phone: 2.5 px/h
  assert.equal(slotMode(576, 144), 'hourly'); // exactly 4 px/h keeps hourly
  assert.equal(slotMode(575, 144), '3-hourly');
  const desk = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 0.4, range: '7d' });
  const phone = chartLayout(forecast, CHART_STYLES.phone, { nowIdx: 0.4, range: '7d' });
  assert.equal(desk.mode, 'hourly');
  assert.equal(desk.n, 45 + 33);
  assert.equal(phone.mode, '3-hourly');
  assert.equal(phone.n, 15 + 33);
  assert.ok(phone.slots.every((s) => s.w === 3), 'phone 7 d: every slot is 3 h');
  // 48 h never aggregates, even on the phone
  assert.equal(chartLayout(forecast, CHART_STYLES.phone, { nowIdx: 0.4 }).n, 45);
});

test('HRRR 3-hour blocks: max sustained, max gust, vector-mean direction (mixed_reference.blocks3)', () => {
  const b = hrrrBlocks(forecast);
  assert.equal(b.length, 15);
  assert.deepEqual(b.map((x) => x.kn).slice(0, 6), [4, 4, 4, 8, 13, 15]);
  assert.deepEqual(b.map((x) => x.gust).slice(0, 6), [5, 4, 6, 15, 24, 25]);
  assert.equal(b[0].dirFrom, 297); // mean of 290/289/313
  assert.equal(b[1].dirFrom, 64); // mean of 51/74/66
  assert.equal(b[2].cloud, 45);
  assert.equal(b[6].precip, 2);
  // 7 d slots never put NBM before the seam
  for (const mode of [false, true]) {
    const s = chartSlots(forecast, '7d', { threeHourly: mode });
    const firstNbm = s.findIndex((x) => x.model === 'NBM');
    assert.equal(s[firstNbm].t, 45);
    assert.ok(s.slice(0, firstNbm).every((x) => x.model === 'HRRR' && x.t + x.w <= 45));
    assert.ok(s.slice(firstNbm).every((x) => x.model === 'NBM'));
  }
});

test('7 d desktop layout: seam, NBM region, bars, dashed-line split, arrows every 3 h, day names on the bottom axis', () => {
  const L = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 0.4, range: '7d' });
  const pxh = 1120 / 144;
  near(L.slot, pxh, 'px per hour');
  assert.equal(L.yMax, 40, 'max gust 32 → ceil(35/10)·10');
  near(L.seam.x, 45 * pxh, 'seam at the HRRR edge');
  assert.equal(L.seam.left.text, 'HRRR');
  assert.equal(L.seam.right.text, 'NBM · 3-hourly');
  near(L.seam.region.w, 1120 - 45 * pxh, 'NBM region to the end');
  assert.equal(L.edge.text, 'ends Tue 9am');
  assert.equal(L.edge.x, 1120);
  // NBM bar for Sat 12–3pm: 3-h slot, bar 0.72 of it, centred
  const sat = L.bars.find((b) => b.t === 75);
  assert.equal(sat.model, 'NBM');
  near(sat.w, Math.round(3 * pxh * 0.72 * 100) / 100, 'NBM bar width', 0.001);
  near(sat.x + sat.w / 2, 76.5 * pxh, 'NBM bar centre');
  const hr = L.bars[0];
  near(hr.w, Math.max(3, Math.round(pxh * 0.72 * 100) / 100), 'HRRR bar width', 0.001);
  // gust points split by model; caps are bar + 2
  assert.equal(L.gust.filter((g) => g.model === 'HRRR').length, 45);
  assert.equal(L.gust.filter((g) => g.model === 'NBM').length, 33);
  const g75 = L.gust.find((g, i) => L.bars[i].t === 75);
  near(g75.capW, sat.w + 2, 'NBM cap');
  // arrows every 3 h in hourly mode: 15 HRRR + 33 NBM
  assert.equal(L.arrows.length, 15 + 33);
  // no hour labels in 7 d; one name per day centred on the bottom axis
  assert.equal(L.labels.length, 0);
  assert.equal(L.ticks.length, 0);
  assert.deepEqual(L.days.map((d) => d.name), ['Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue']);
  assert.ok(L.days.every((d) => d.bottom && d.labelY === 310 && d.anchor === 'middle'));
  near(L.days[0].labelX, 7.5 * pxh, 'Wed centred on its visible 15 h');
  near(L.days[1].labelX, 27 * pxh, 'Thu centred on 15–39');
  assert.equal(L.days[0].divider, null);
  assert.deepEqual(L.days.slice(1).map((d) => d.i), [15, 39, 63, 87, 111, 135]);
  assert.ok(L.days.slice(1).every((d) => d.divider.y1 === 22 && d.divider.y2 === 278));
  // selection and hit-testing work on mixed-width slots
  const i = L.bars.indexOf(sat);
  assert.equal(hourAtX(L, 76 * pxh), i);
  assert.equal(hourAtX(L, 44.5 * pxh), 44);
  assert.equal(hourAtX(L, 1120), null);
  near(selectionGeometry(L, i).cx, 76.5 * pxh, 'selection rule at the block centre');
});

test('7 d phone layout: 3-hourly, arrows every 6 h', () => {
  const P = chartLayout(forecast, CHART_STYLES.phone, { nowIdx: 0.4, range: '7d' });
  assert.ok(P.arrows.every((a) => P.slots[a.i].t % 6 === 0));
  assert.equal(P.arrows.length, 8 + 16);
  near(P.seam.x, 45 * (358 / 144), 'seam');
});

test('7 d without NBM: stops at the HRRR edge, edge label names NBM unavailable, no seam', () => {
  const L = chartLayout(nbmNull, CHART_STYLES.desktop, { nowIdx: 0.4, range: '7d' });
  assert.equal(L.n, 45);
  assert.equal(L.seam, null);
  assert.equal(L.edge.x, 1120);
  assert.equal(L.edge.text, 'ends Fri 5am · NBM unavailable');
  assert.ok(L.bars.every((b) => b.model === 'HRRR'));
  assert.equal(rangeTitle(nbmNull, '7d'), 'Wed 9am → Fri 5am');
  assert.equal(rangeHint(nbmNull, '7d'), 'HRRR to Fri 5am · NBM unavailable');
});

test('sun markers: rise and set every day in 7 d (computed past the payload days), never dawn/dusk', () => {
  assert.equal(forecast.sun.length, 7, 'payload Wed–Fri + computed Sat–Tue');
  // payload days are kept verbatim
  assert.equal(forecast.sun[0].rise.getTime(), payload.sun[0].rise * 1000);
  const L = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 0.4, range: '7d' });
  assert.ok(L.sun.every((s) => s.kind === 'rise' || s.kind === 'set'));
  assert.equal(L.sun.filter((s) => s.kind === 'set').length, 6, 'a sunset each day Wed–Mon');
  assert.equal(L.sun.filter((s) => s.kind === 'rise').length, 6, 'a sunrise each day Thu–Tue');
  // Sat sunrise lands near 07:4x local
  const satRise = L.sun.filter((s) => s.kind === 'rise')[2].at;
  assert.ok(Math.abs(satRise.getTime() - (forecast.start.getTime() + (72 - 9 + 7.75) * HOUR_MS)) < 20 * MINUTE_MS);
  // 48 h keeps the three markers it had
  assert.deepEqual(chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 0.4 }).sun.map((s) => s.kind), ['set', 'rise', 'set']);
});

test('slot labels: HRRR hours untagged, NBM blocks as a span', () => {
  assert.equal(spanText(12, 15), '12–3pm');
  assert.equal(spanText(9, 12), '9am–12pm');
  assert.equal(spanText(21, 24), '9pm–12am');
  assert.equal(spanText(0, 3), '12–3am');
  assert.equal(spanText(6, 9), '6–9am');
  const sat = forecast.extended.blocks[10];
  assert.equal(slotLabel(sat, TZ), 'Sat 12–3pm');
  assert.equal(slotLabel({ ...forecast.hours[15], w: 1, start: new Date(forecast.start.getTime() + 15 * HOUR_MS) }, TZ), 'Thu 12am · midnight');
  assert.equal(slotTableLabel(forecast.extended.blocks[0], TZ), 'Fri 06–09');
  assert.equal(slotTableLabel(sat, TZ), 'Sat 12–15');
  assert.equal(slotTableLabel(forecast.extended.blocks[5], TZ, { compact: true }), '21–00');
});

test('peak chip across the 7-day range: "peak G32 · Sat 1pm · NBM"', () => {
  assert.equal(rangePeak(forecast, 0.4).text, 'peak G32 · Sat 1pm · NBM');
  assert.equal(rangePeak(forecast, 0.4).model, 'NBM');
  // HRRR-only 7 d: the HRRR maximum, untagged
  assert.equal(rangePeak(nbmNull, 0.4).text, 'peak G25 · Thu 12am');
  // the scan starts at the now hour: past peaks do not count
  assert.equal(rangePeak(nbmNull, 16).text, 'peak G24 · Thu 1am');
});

test('sky tone, rain ticks and words (sky_reference.py thresholds)', () => {
  assert.equal(skyTone(0), 'clear');
  assert.equal(skyTone(24), 'clear');
  assert.equal(skyTone(25), 'partly');
  assert.equal(skyTone(69), 'partly');
  assert.equal(skyTone(70), 'overcast');
  assert.equal(skyTone(null), null);
  assert.equal(skyWord(10), 'Clear');
  assert.equal(skyWord(45), 'Partly cloudy');
  assert.equal(skyWord(100), 'Overcast');
  assert.deepEqual([0, 0.1, 0.4, 0.5, 1.2, 1.49, 1.5, 2.0, null].map(rainTicks), [0, 1, 1, 2, 2, 2, 3, 3, 0]);
  assert.equal(rainWord(0), null);
  assert.equal(rainWord(0.4), 'light rain');
  assert.equal(rainWord(1.2), 'rain');
  assert.equal(rainWord(2.0), 'heavy rain');
});

test('sky cells: HRRR in threes from index 0, then the NBM blocks (7 d only)', () => {
  const c48 = skyCells(forecast, '48h');
  assert.equal(c48.length, 15);
  assert.deepEqual(c48.map((c) => c.tone).slice(0, 5), ['clear', 'clear', 'partly', 'overcast', 'overcast']);
  assert.deepEqual(c48.map((c) => c.ticks), [0, 0, 0, 0, 1, 2, 3, 2, 0, 0, 0, 0, 0, 1, 0]);
  const c7 = skyCells(forecast, '7d');
  assert.equal(c7.length, 15 + 33);
  assert.equal(c7[15].model, 'NBM');
  assert.equal(c7[15].t, 45);
  assert.equal(skyCells(nbmNull, '7d').length, 15);
  // geometry: rect inset 0.5, y 2, h 10, rx 2 in the page; ticks 8 → 13, evenly spaced
  const L = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 0.4 });
  assert.equal(L.skyH, 16);
  const slot = 1120 / 45;
  const cell = L.sky[6]; // 3 ticks
  near(cell.x, 18 * slot + 0.5, 'cell x');
  near(cell.w, 3 * slot - 1, 'cell w');
  assert.equal(cell.y, 2);
  assert.equal(cell.h, 10);
  assert.equal(cell.ticks.length, 3);
  near(cell.ticks[0].x, 18 * slot + (3 * slot) / 4, 'tick 1');
  assert.deepEqual([cell.ticks[0].y1, cell.ticks[0].y2], [8, 13]);
  // no sky data → no band, no offset (48 h renders exactly as before)
  assert.equal(chartLayout(hrrrOnly, CHART_STYLES.desktop, { nowIdx: 0.4 }).skyH, 0);
});

test('temperature: integer, °F default, °C option, appended to the readout text', () => {
  assert.equal(parseTempUnit('c'), 'C');
  assert.equal(parseTempUnit('F'), 'F');
  assert.equal(parseTempUnit('k'), null);
  assert.equal(tempValue(8.9, 'F'), 48);
  assert.equal(tempValue(8.9, 'C'), 9);
  assert.equal(tempValue(-0.4, 'C'), 0);
  assert.ok(!Object.is(tempValue(-0.4, 'C'), -0));
  assert.equal(tempValue(-17.9, 'F'), 0);
  assert.equal(formatTemp(7.9), '46°F');
  assert.equal(formatTemp(7.9, 'C'), '8°C');
  assert.equal(formatTemp(null), null);
  // Thu 12am: overcast, 1.2 mm/h, 7.9 °C
  assert.deepEqual(conditionsParts(forecast.hours[15]), ['Overcast', 'rain', '46°F']);
  assert.deepEqual(conditionsParts(forecast.hours[0], 'C'), ['Clear', '10°C']);
  assert.deepEqual(conditionsParts(forecast.extended.blocks[10]), ['Overcast', 'heavy rain', '51°F']);
});

test('table rows: hourly to the seam, header "NBM from Fri 6am · 3-hourly", then 3-h NBM rows', () => {
  const r48 = tableRows(forecast, '48h');
  assert.equal(r48.length, 45);
  const r7 = tableRows(forecast, '7d');
  assert.equal(r7.length, 45 + 1 + 33);
  assert.deepEqual(r7[45], { kind: 'nbm-header', text: 'NBM from Fri 6am · 3-hourly' });
  assert.equal(r7[46].kind, 'block');
  assert.equal(r7[46].slot.model, 'NBM');
  assert.equal(tableRows(nbmNull, '7d').length, 45);
  assert.equal(tableCaption(forecast, 0.4, { range: '7d' }), 'hourly to Fri 5am, then 3-hourly to Tue 9am · NBM rows tagged');
  assert.equal(tableCaption(forecast, 0.4, { range: '7d', compact: true }), 'to Tue 9am · NBM 3-hourly');
  assert.equal(tableCaption(nbmNull, 0.4, { range: '7d' }), '45 hours · Wed 9am → Fri 5am');
});

test('titles and hint per range', () => {
  assert.equal(rangeTitle(forecast, '48h'), 'Wed 9am → Fri 5am');
  assert.equal(rangeTitle(forecast, '7d'), 'Wed 9am → Tue 9am');
  assert.equal(rangeHint(forecast, '48h'), 'hover or touch a bar for that hour');
  assert.equal(rangeHint(forecast, '7d'), 'HRRR hourly to Fri 5am · NBM 3-hourly beyond · hover for a block');
  assert.ok(chartAriaLabel(forecast, '7d').startsWith('7-day wind chart: sustained 2 to 18 knots, gusts to 32 knots; HRRR hourly to Friday 05:00, then NBM 3-hourly, ends Tuesday 09:00'));
  assert.equal(chartAriaLabel(forecast), '45-hour wind chart: sustained 2 to 15 knots, gusts to 25 knots, ends Friday 05:00');
});

test('trust line in 7 d names both runs; NBM staleness ambers only its run label', () => {
  const line = (f, now, extra = {}) => trustLine(f, trustState({ forecast: f, now }), TZ, { range: '7d', now, ...extra });
  const fresh = line(forecast, NOW);
  assert.equal(fresh.text, 'as of 09:00 PDT · HRRR 15Z + NBM 13Z · forecast ends Tue 9am');
  assert.equal(fresh.amber, false);
  assert.equal(fresh.nbmStale, false);
  assert.deepEqual(fresh.segments.map((s) => s.amber), [false, false, false]);
  assert.equal(line(forecast, NOW, { compact: true }).text, 'as of 09:00 PDT · HRRR 15Z + NBM 13Z · ends Tue 9am');
  // NBM fetched 2 h before HRRR: HRRR fresh, NBM stale
  const staleNbm = toForecast({ ...payload, extended: { ...payload.extended, fetched: payload.fetched - 2 * 3600 } });
  const s = line(staleNbm, NOW);
  assert.equal(s.amber, false);
  assert.equal(s.nbmStale, true);
  assert.deepEqual(s.segments.map((x) => [x.text, x.amber]), [
    ['as of 09:00 PDT · HRRR 15Z + ', false],
    ['NBM 13Z', true],
    [' · forecast ends Tue 9am', false],
  ]);
  // 48 h, or 7 d without NBM, keeps the HRRR-only line
  assert.equal(trustLine(forecast, trustState({ forecast, now: NOW }), TZ, { now: NOW }).text, 'as of 09:00 PDT · HRRR 15Z · forecast ends Fri 5am');
  assert.equal(line(nbmNull, NOW).text, 'as of 09:00 PDT · HRRR 15Z · forecast ends Fri 5am');
});
