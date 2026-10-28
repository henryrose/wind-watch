// Web → iOS app awareness (docs/design/web-app-awareness/HANDOFF.md).
// Pure: the strip's show rule and the complication drawing. No DOM.
import { arrowRotation, beaufortStep, compassLabel, formatHHMM, nowIndex, yDomainMax } from './derive.js';

export const APP_STORE_URL = 'https://apps.apple.com/us/app/wind-watch-sailing/id6825620891';
export const STRIP_KEY = 'appStripDismissed';
export const STRIP_SNOOZE_MS = 30 * 24 * 60 * 60 * 1000;

// --- Platform -------------------------------------------------------------

// iPhone / iPod / iPad, including iPadOS which reports itself as a Mac.
export function isIOS(ua, maxTouchPoints = 0) {
  if (/iPhone|iPod|iPad/.test(ua)) return true;
  return /Macintosh/.test(ua) && maxTouchPoints > 1;
}

// Safari proper, the one browser that draws the Smart App Banner. Other iOS
// browsers add their own token (CriOS, FxiOS, EdgiOS…); in-app browsers
// (Slack, Facebook, Instagram, Gmail…) either add a token or drop "Safari/".
const NOT_SAFARI = /CriOS|FxiOS|EdgiOS|OPiOS|OPT\/|DuckDuckGo|YaBrowser|GSA\/|FBAN|FBAV|FB_IAB|Instagram|LinkedInApp|Line\/|Twitter|Slack|Snapchat|Pinterest|GoogleApp|Gmail|Messenger/;
export function isIOSSafari(ua, maxTouchPoints = 0) {
  return isIOS(ua, maxTouchPoints) && /Safari\//.test(ua) && !NOT_SAFARI.test(ua);
}

// §1.4: iOS, not Safari, and not dismissed within the last 30 days.
export function shouldShowStrip({ ua, maxTouchPoints = 0, dismissedAt = null, now = Date.now() }) {
  if (!isIOS(ua, maxTouchPoints) || isIOSSafari(ua, maxTouchPoints)) return false;
  const t = Number(dismissedAt);
  if (dismissedAt != null && Number.isFinite(t) && now - t < STRIP_SNOOZE_MS) return false;
  return true;
}

// --- Complication drawing (§2, ports comp_mini) ---------------------------

// The plate is always black (it is a watch face), so it always uses the dark ramp.
const RAMP_DARK = ['#5C6B7A', '#5C6B7A', '#4FA3D8', '#3FC2A0', '#8DD44A', '#F2D13D', '#F59A2B', '#EC5A2A', '#E0245E', '#A32CD1', '#F5F5F7'];
const rampColor = (kn) => RAMP_DARK[Math.min(beaufortStep(kn), 10)];
const KITE = 'M0,-0.5 L0.38,0.5 L0,0.2 L-0.38,0.5 Z';
const f1 = (n) => (Math.round(n * 10) / 10).toString();

// The next 12 hours from the current hour, never padded past the horizon.
export function next12(forecast, now) {
  const i = Math.max(0, Math.floor(nowIndex(forecast, now)));
  return forecast.hours.slice(i, i + 12);
}

// Returns the drawing as an HTML string: a text row (HTML so long numbers
// reflow) over an SVG of 12 bars with gust caps and a gust line. W×H is the
// whole plate; the text row is the top 28 px as in the reference.
export function compMiniHtml(forecast, now, { W = 172, H = 64 } = {}) {
  const TOP = 28;
  const hours = forecast ? next12(forecast, now) : [];
  const h = hours[0];
  const label = h
    ? `Rectangular complication: ${h.kn} knots, gusts ${h.gust}, from ${compassLabel(h.dirFrom)}, next ${hours.length} hours`
    : 'Rectangular complication';
  const text = h
    ? `<span class="cm-kn">${h.kn}</span><span class="cm-g">G${h.gust}</span>` +
      `<svg class="cm-arrow" viewBox="-0.5 -0.5 1 1" width="9" height="9" aria-hidden="true"><path d="${KITE}" transform="rotate(${arrowRotation(h.dirFrom)})" fill="#FFFFFF"/></svg>` +
      `<span class="cm-from">from ${compassLabel(h.dirFrom)}</span>` +
      `<span class="cm-asof">as of ${formatHHMM(forecast.fetched, forecast.location.tz)}</span>`
    : `<span class="cm-kn cm-dash">—</span>`;

  const plotH = H - TOP - 4;
  const bh = H - TOP;
  const slot = W / 12;
  const yMax = yDomainMax(hours);
  const Y = (v) => bh - 4 - (Math.min(v, yMax) / yMax) * plotH;
  const bw = slot * 0.72 - 1;
  const parts = [];
  const pts = [];
  hours.forEach((hr, i) => {
    const x = i * slot + 4;
    const y = Y(hr.kn);
    const gy = Y(hr.gust);
    parts.push(`<rect x="${f1(x + 0.5)}" y="${f1(y)}" width="${f1(bw)}" height="${f1(bh - 4 - y)}" rx="1.5" fill="${rampColor(hr.kn)}"/>`);
    parts.push(`<line x1="${f1(x - 1)}" x2="${f1(x + bw + 1)}" y1="${f1(gy)}" y2="${f1(gy)}" stroke="#FFFFFF" stroke-width="1"/>`);
    pts.push(`${f1(x + slot * 0.36)},${f1(gy)}`);
  });
  if (pts.length > 1) parts.push(`<polyline points="${pts.join(' ')}" fill="none" stroke="#FFFFFF" stroke-opacity="0.75" stroke-width="1"/>`);

  return `<div class="comp-mini" role="img" aria-label="${label}" style="width:${W}px;height:${H}px">` +
    `<div class="cm-row" aria-hidden="true">${text}</div>` +
    `<svg class="cm-bars" width="${f1(W)}" height="${bh}" viewBox="0 0 ${f1(W)} ${bh}" aria-hidden="true">${parts.join('')}</svg>` +
    `</div>`;
}
