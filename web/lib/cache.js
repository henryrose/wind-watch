// Wind Watch — cache record for live mode. Pure: no localStorage here, the
// page wraps storage access itself. A record is
//   { etag, body, savedAt, lastChecked, lastCheckOK }
// body is the parsed wire payload; savedAt is when a 200 last replaced it;
// lastChecked is the last attempt of any outcome; times are unix ms.

export const CACHE_KEY = 'ww.payload.v1';

export function parseRecord(json) {
  if (typeof json !== 'string' || !json) return null;
  try {
    const r = JSON.parse(json);
    if (!r || typeof r !== 'object') return null;
    if (!r.body || r.body.v !== 1 || !Number.isInteger(r.body.hours)) return null;
    if (typeof r.etag !== 'string') return null;
    if (!Number.isFinite(r.savedAt) || !Number.isFinite(r.lastChecked)) return null;
    return {
      etag: r.etag,
      body: r.body,
      savedAt: r.savedAt,
      lastChecked: r.lastChecked,
      lastCheckOK: Boolean(r.lastCheckOK),
    };
  } catch {
    return null;
  }
}

export function serializeRecord(record) {
  return JSON.stringify(record);
}

// Fold one check outcome into the previous record.
//   { status: 200, etag, body, now }     → fresh record
//   { status: 304, now }                 → keep body, mark checked OK
//   { status: 'error' | 5xx | 503, now } → keep body, mark checked failed
// Returns the next record, or null when there is nothing to show.
export function recordAfterCheck(prev, outcome) {
  const now = outcome.now;
  if (outcome.status === 200 && outcome.body) {
    return {
      etag: outcome.etag || '',
      body: outcome.body,
      savedAt: now,
      lastChecked: now,
      lastCheckOK: true,
    };
  }
  if (!prev) return null;
  if (outcome.status === 304) {
    return { ...prev, lastChecked: now, lastCheckOK: true };
  }
  return { ...prev, lastChecked: now, lastCheckOK: false };
}
