// node --test — app awareness: the strip's show rule and the complication drawing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { HOUR_MS, toForecast } from '../lib/derive.js';
import { STRIP_SNOOZE_MS, compMiniHtml, isIOS, isIOSSafari, next12, shouldShowStrip } from '../lib/awareness.js';

const here = dirname(fileURLToPath(import.meta.url));
const payload = JSON.parse(readFileSync(join(here, '..', '..', 'fixtures', 'payload-reference.json'), 'utf8'));
const forecast = toForecast(payload);

const UA = {
  safari: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1',
  chromeIOS: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/141.0 Mobile/15E148 Safari/604.1',
  firefoxIOS: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/144.0 Mobile/15E148 Safari/605.1.15',
  webview: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
  slack: 'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Slack/25.10',
  ipadSafari: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  macSafari: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
  android: 'Mozilla/5.0 (Linux; Android 16; Pixel 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36',
};

test('iOS detection, including iPadOS reporting as a Mac', () => {
  assert.equal(isIOS(UA.safari), true);
  assert.equal(isIOS(UA.ipadSafari, 5), true);
  assert.equal(isIOS(UA.macSafari, 0), false);
  assert.equal(isIOS(UA.android), false);
});

test('Safari is the only iOS browser left to the Smart Banner', () => {
  assert.equal(isIOSSafari(UA.safari), true);
  assert.equal(isIOSSafari(UA.ipadSafari, 5), true);
  for (const k of ['chromeIOS', 'firefoxIOS', 'webview', 'slack']) assert.equal(isIOSSafari(UA[k]), false, k);
});

test('strip shows only on iOS non-Safari', () => {
  for (const k of ['chromeIOS', 'firefoxIOS', 'webview', 'slack']) assert.equal(shouldShowStrip({ ua: UA[k] }), true, k);
  for (const k of ['safari', 'macSafari', 'android']) assert.equal(shouldShowStrip({ ua: UA[k] }), false, k);
  assert.equal(shouldShowStrip({ ua: UA.ipadSafari, maxTouchPoints: 5 }), false);
});

test('a dismissal snoozes the strip for 30 days', () => {
  const now = 2_000_000_000_000;
  const ua = UA.chromeIOS;
  assert.equal(shouldShowStrip({ ua, now, dismissedAt: String(now - 1000) }), false);
  assert.equal(shouldShowStrip({ ua, now, dismissedAt: String(now - STRIP_SNOOZE_MS + 1) }), false);
  assert.equal(shouldShowStrip({ ua, now, dismissedAt: String(now - STRIP_SNOOZE_MS) }), true);
  assert.equal(shouldShowStrip({ ua, now, dismissedAt: 'garbage' }), true);
});

test('drawing uses the next 12 hours from the current hour', () => {
  const now = new Date(forecast.start.getTime() + 3.5 * HOUR_MS);
  const hours = next12(forecast, now);
  assert.equal(hours.length, 12);
  assert.deepEqual(hours[0], forecast.hours[3]);
  const html = compMiniHtml(forecast, now);
  assert.equal((html.match(/<rect /g) || []).length, 12);
  assert.match(html, new RegExp(`<span class="cm-kn">${forecast.hours[3].kn}</span><span class="cm-g">G${forecast.hours[3].gust}</span>`));
  assert.match(html, /as of \d\d:\d\d/);
  assert.match(html, /width:172px;height:64px/);
});

test('drawing is never padded past the horizon', () => {
  const n = forecast.hours.length;
  const now = new Date(forecast.start.getTime() + (n - 5) * HOUR_MS);
  assert.equal(next12(forecast, now).length, 5);
  assert.equal((compMiniHtml(forecast, now).match(/<rect /g) || []).length, 5);
  const past = new Date(forecast.start.getTime() + (n + 2) * HOUR_MS);
  assert.match(compMiniHtml(forecast, past), /cm-dash/);
  assert.match(compMiniHtml(null, past), /cm-dash/);
});
