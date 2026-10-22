// node --test — the chart port against docs/design/reference/charts/webhover.svg
// (the output of `chart_reference.py webhover`: 1120×300, top 40, bottom 22,
// now = 0.4, hour 15 selected). The reference rounds every coordinate to one
// decimal, so the tolerance is 0.06 px except where noted.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import {
  CHART_STYLES,
  HOUR_MS,
  chartLayout,
  chartTitle,
  horizonLabel,
  hour12,
  hourAt,
  hourAtX,
  scrubLabel,
  selectionGeometry,
  tickLabel,
  toForecast,
} from '../lib/derive.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const payload = JSON.parse(readFileSync(join(root, 'fixtures', 'payload-reference.json'), 'utf8'));
const forecast = toForecast(payload);
const TZ = forecast.location.tz;
const ref = readFileSync(join(root, 'docs', 'design', 'reference', 'charts', 'webhover.svg'), 'utf8');

const NOW_IDX = 0.4;
const L = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: NOW_IDX });

const TOL = 0.06;
const near = (a, b, msg, tol = TOL) => assert.ok(Math.abs(a - b) <= tol, `${msg}: ${a} vs ${b}`);
const attrs = (tag) => Object.fromEntries([...tag.matchAll(/([\w:-]+)="([^"]*)"/g)].map((m) => [m[1], m[2]]));
const tags = (name) => [...ref.matchAll(new RegExp(`<${name}\\b[^>]*>`, 'g'))].map((m) => m[0]);
const num = (s) => Number(s);

test('geometry constants: slot, bar width, y domain, plot box', () => {
  near(L.slot, 1120 / 45, 'slot');
  assert.equal(L.bw, 17.92);
  assert.equal(L.capW, 19.92);
  assert.equal(L.yMax, 30);
  assert.equal(L.top, 40);
  assert.equal(L.plotH, 238);
  assert.equal(L.plotBottom, 278);
  assert.equal(L.bot, 22);
  assert.equal(L.n, 45);
  assert.ok(ref.includes('<rect x="0" y="40" width="1120.0" height="238.0" fill="url(#dndh)"/>'));
});

test('gradient stops match the reference (Thu dawn/rise are one minute later in the fixture)', () => {
  const refStops = tags('stop').map(attrs).map((a) => [num(a.offset), num(a['stop-opacity'])]);
  assert.equal(refStops.length, 8);
  assert.equal(L.stops.length, 8);
  L.stops.forEach((s, i) => {
    // 07:08/07:40 in the script vs 07:09/07:41 in the fixture = 1/60 h / 45 h = 0.00037
    near(s.offset, refStops[i][0], `stop ${i} offset`, 0.0005);
    near(Math.round(0.07 * s.value * 1000) / 1000, refStops[i][1], `stop ${i} opacity`, 1e-9);
  });
  assert.equal(L.stops[0].value, 1, 'starts in day');
  assert.equal(L.stops[7].value, 0, 'ends in night; Fri dawn is past the edge and not emitted');
});

test('gridlines every 10 below ymax, labels right-aligned inside the plot', () => {
  assert.deepEqual(L.grid.map((g) => g.v), [10, 20]);
  const refLines = tags('line').map(attrs).filter((a) => a['stroke-opacity'] === '0.12');
  assert.equal(refLines.length, 2);
  L.grid.forEach((g, i) => {
    near(g.y, num(refLines[i].y1), `grid ${g.v} y`);
    assert.equal(g.labelX, 1118);
    near(g.labelY, num(refLines[i].y1) - 3, `grid ${g.v} label y`);
  });
  const refLabels = tags('text').map(attrs).filter((a) => a.x === '1118');
  assert.deepEqual(refLabels.map((a) => a.y), L.grid.map((g) => g.labelY.toFixed(1)));
});

test('sun dots at the plot top edge; Fri dawn/rise not drawn', () => {
  const refDots = tags('circle').map(attrs);
  assert.equal(refDots.length, 3);
  assert.equal(L.sun.length, 3);
  assert.deepEqual(L.sun.map((s) => s.kind), ['set', 'rise', 'set']);
  L.sun.forEach((s, i) => {
    assert.equal(s.y, 39);
    // the fixture's Thursday sunrise is 07:41 where the script used 07:40
    near(s.x, num(refDots[i].cx), `sun ${i} x`, s.kind === 'rise' ? 0.5 : TOL);
  });
});

test('bars: x, y, width, height and colour for all 45 hours', () => {
  const refBars = tags('rect').map(attrs).filter((a) => a.rx === '1.5');
  assert.equal(refBars.length, 45);
  const RAMP = { calm: '#5C6B7A', 2: '#4FA3D8', 3: '#3FC2A0', 4: '#8DD44A', 5: '#F2D13D', 6: '#F59A2B', 7: '#EC5A2A', 8: '#E0245E', 9: '#A32CD1', 10: '#F5F5F7' };
  L.bars.forEach((b, i) => {
    const r = refBars[i];
    near(b.x, num(r.x), `bar ${i} x`);
    near(b.y, num(r.y), `bar ${i} y`);
    assert.equal(b.w, num(r.width), `bar ${i} w`);
    near(b.h, num(r.height), `bar ${i} h`);
    assert.equal(RAMP[b.token], r.fill, `bar ${i} colour`);
    near(b.y + b.h, 278, `bar ${i} sits on the baseline`, 1e-9);
  });
});

test('gust polyline through cap centres; caps are bar + 2 wide', () => {
  const pts = attrs(tags('polyline')[0]).points.split(' ').map((p) => p.split(',').map(num));
  assert.equal(pts.length, 45);
  L.gust.forEach((g, i) => {
    near(g.x, pts[i][0], `gust ${i} x`);
    near(g.y, pts[i][1], `gust ${i} y`);
  });
  const caps = tags('line').map(attrs).filter((a) => a['stroke-linecap'] === 'round');
  assert.equal(caps.length, 45);
  L.gust.forEach((g, i) => {
    near(g.x - L.capW / 2, num(caps[i].x1), `cap ${i} x1`);
    near(g.x + L.capW / 2, num(caps[i].x2), `cap ${i} x2`);
    near(g.y, num(caps[i].y1), `cap ${i} y`);
  });
});

test('arrows every hour at plotBottom + bot/2, rotated dirFrom + 180', () => {
  const refArrows = tags('g').map((t) => t.match(/translate\(([\d.]+),([\d.]+)\) rotate\((\d+)\)/)).map((m) => m.slice(1).map(num));
  assert.equal(refArrows.length, 45);
  assert.equal(L.arrows.length, 45);
  assert.equal(L.arrowSize, 10);
  L.arrows.forEach((a, i) => {
    near(a.x, refArrows[i][0], `arrow ${i} x`);
    assert.equal(a.y, 289);
    assert.equal(a.rot, refArrows[i][2], `arrow ${i} rotation`);
  });
});

test('ticks every 3 h (hour-of-day), 3 tall; labels at H + 10 in 12-hour text', () => {
  const refTicks = tags('line').map(attrs).filter((a) => a.y1 === '278.0' && a.y2 === '281.0');
  assert.equal(refTicks.length, 15);
  assert.equal(L.ticks.length, 15);
  L.ticks.forEach((t, i) => {
    near(t.x, num(refTicks[i].x1), `tick ${i} x`);
    assert.equal(t.y1, 278);
    assert.equal(t.y2, 281);
  });
  const refLabels = [...ref.matchAll(/<text x="([\d.]+)" y="310"[^>]*>([^<]+)<\/text>/g)].map((m) => [num(m[1]), m[2]]);
  assert.equal(refLabels.length, 15);
  assert.equal(L.labels.length, 15);
  L.labels.forEach((l, i) => {
    near(l.x, refLabels[i][0], `label ${i} x`);
    assert.equal(l.text, refLabels[i][1], `label ${i} text`);
    assert.equal(l.y, 310);
  });
  assert.deepEqual(L.labels.slice(0, 8).map((l) => l.text), ['9am', 'noon', '3pm', '6pm', '9pm', '12am', '3am', '6am']);
});

test('day band: name at x + 5 / top − 22, dotted divider at each midnight but not the first day', () => {
  const refDays = [...ref.matchAll(/<text x="([\d.]+)" y="18"[^>]*>(\w+)<\/text>/g)].map((m) => [num(m[1]), m[2]]);
  const refDividers = tags('line').map(attrs).filter((a) => a['stroke-dasharray'] === '2 3');
  assert.deepEqual(refDays.map((d) => d[1]), ['Wed', 'Thu', 'Fri']);
  assert.equal(refDividers.length, 2);
  assert.deepEqual(L.days.map((d) => d.name), ['Wed', 'Thu', 'Fri']);
  assert.deepEqual(L.days.map((d) => d.i), [0, 15, 39]);
  L.days.forEach((d, i) => {
    near(d.labelX, refDays[i][0], `day ${d.name} label x`);
    assert.equal(d.labelY, 18);
  });
  assert.equal(L.days[0].divider, null);
  L.days.slice(1).forEach((d, i) => {
    near(d.divider.x, num(refDividers[i].x1), `divider ${d.name} x`);
    assert.equal(d.divider.y1, 22);
    assert.equal(d.divider.y2, 278);
  });
  // README nit: "now" at 0.4 h would sit under "Wed", so Wed is hidden.
  assert.equal(L.days[0].hidden, true);
  assert.equal(L.days[1].hidden, false);
  const later = chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 3.5 });
  assert.equal(later.days[0].hidden, false, 'Wed shows again once now has moved right');
});

test('now rule at x(0.4) with its label at x + 4 / top − 8', () => {
  near(L.now.x, 10.0, 'now x');
  assert.equal(L.now.y1, 34);
  assert.equal(L.now.y2, 278);
  near(L.now.labelX, 14.0, 'now label x');
  assert.equal(L.now.labelY, 32);
  assert.ok(ref.includes('<line x1="10.0" x2="10.0" y1="34" y2="278.0" stroke="#FFFFFF" stroke-width="1.5"/>'));
  assert.ok(ref.includes('<text x="14.0" y="32"'));
  assert.equal(chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: -1 }).now, null);
  assert.equal(chartLayout(forecast, CHART_STYLES.desktop, { nowIdx: 46 }).now, null);
});

test('horizon edge at x(45) with "ends Fri 5am" right-aligned at x − 4', () => {
  assert.equal(L.edge.x, 1120);
  assert.equal(L.edge.y1, 34);
  assert.equal(L.edge.y2, 278);
  assert.equal(L.edge.labelX, 1116);
  assert.equal(L.edge.labelY, 32);
  assert.equal(L.edge.text, 'ends Fri 5am');
  assert.ok(ref.includes('<line x1="1120.0" x2="1120.0" y1="34" y2="278.0" stroke="#FFFFFF" stroke-opacity="0.7" stroke-width="1" stroke-dasharray="3 3"/>'));
  assert.ok(ref.includes('>ends Fri 5am</text>'));
});

test('selection of hour 15: rule through the slot centre, outline outset 1.5 with rx 2.5', () => {
  const s = selectionGeometry(L, 15);
  const refRule = attrs(ref.match(/<line [^>]*y2="300.0" stroke="#FFFFFF" stroke-width="1.5"\/>/)[0]);
  const refOutline = attrs(tags('rect').find((t) => t.includes('rx="2.5"')));
  near(s.rule.x, num(refRule.x1), 'rule x');
  assert.equal(s.rule.y1, 34);
  assert.equal(s.rule.y2, 300);
  near(s.outline.x, num(refOutline.x), 'outline x');
  near(s.outline.y, num(refOutline.y), 'outline y');
  near(s.outline.w, num(refOutline.width), 'outline w');
  near(s.outline.h, num(refOutline.height), 'outline h');
  assert.equal(s.outline.rx, 2.5);
  assert.equal(selectionGeometry(L, 45), null);
  // the reference dims every other bar to 0.45
  const dimmed = tags('rect').filter((t) => t.includes('rx="1.5"') && t.includes('fill-opacity="0.45"'));
  assert.equal(dimmed.length, 44);
});

test('hourAtX = floor(x / slot) inside the plot', () => {
  assert.equal(hourAtX(L, 0), 0);
  assert.equal(hourAtX(L, 385.8), 15);
  assert.equal(hourAtX(L, 1119.9), 44);
  assert.equal(hourAtX(L, 1120), null);
  assert.equal(hourAtX(L, -0.1), null);
});

test('phone style: 358×200, top 22 / bottom 16, arrows every 3 h, labels every 6 h, no day band', () => {
  const P = chartLayout(forecast, CHART_STYLES.phone, { nowIdx: NOW_IDX });
  const refP = readFileSync(join(root, 'docs', 'design', 'reference', 'charts', 'webphone48.svg'), 'utf8');
  assert.equal(P.plotH, 162);
  assert.equal(P.plotBottom, 184);
  near(P.slot, 358 / 45, 'slot');
  assert.equal(P.bw, 5.73);
  assert.equal(P.font, 11);
  assert.equal(P.arrowSize, 9);
  assert.equal(P.arrows.length, 15);
  assert.deepEqual(P.arrows.map((a) => a.i).slice(0, 4), [0, 3, 6, 9]);
  assert.equal(P.arrows[0].y, 192);
  assert.deepEqual(P.labels.map((l) => l.text), ['9am', '3pm', '9pm', '3am', '9am', '3pm', '9pm', '3am']);
  assert.deepEqual(P.labels.map((l) => l.y), Array(8).fill(210));
  assert.equal(P.days.length, 0);
  // bars and labels line up with the reference phone fragment (24-h text there is pre-review)
  const refBars = [...refP.matchAll(/<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="1.5"/g)];
  assert.equal(refBars.length, 45);
  P.bars.forEach((b, i) => {
    near(b.x, num(refBars[i][1]), `phone bar ${i} x`);
    near(b.y, num(refBars[i][2]), `phone bar ${i} y`);
    near(b.h, num(refBars[i][4]), `phone bar ${i} h`);
  });
  const refLabelX = [...refP.matchAll(/<text x="([\d.]+)" y="210"/g)].map((m) => num(m[1]));
  assert.deepEqual(refLabelX.length, 8);
  P.labels.forEach((l, i) => near(l.x, refLabelX[i], `phone label ${i} x`));
  near(P.now.x, 3.2, 'phone now x'); // reference label at 7.2 = x + 4
  near(P.edge.x, 358, 'phone edge x');
});

test('12-hour labels: ticks, title, edge, scrub', () => {
  assert.equal(hour12(0), '12am');
  assert.equal(hour12(9), '9am');
  assert.equal(hour12(12), '12pm');
  assert.equal(hour12(17), '5pm');
  assert.equal(hour12(23), '11pm');
  assert.equal(tickLabel(12), 'noon');
  assert.equal(tickLabel(0), '12am');
  assert.equal(chartTitle(forecast), 'Wed 9am → Fri 5am');
  assert.equal(horizonLabel(forecast), 'ends Fri 5am');
  assert.equal(scrubLabel(hourAt(forecast, 15), TZ), 'Thu 12am · midnight');
  assert.equal(scrubLabel(hourAt(forecast, 27), TZ), 'Thu 12pm · noon');
  assert.equal(scrubLabel(hourAt(forecast, 30), TZ), 'Thu 3pm');
  assert.equal(scrubLabel(hourAt(forecast, 0), TZ), 'Wed 9am');
  assert.equal(hourAt(forecast, 44).getTime(), forecast.start.getTime() + 44 * HOUR_MS);
});
