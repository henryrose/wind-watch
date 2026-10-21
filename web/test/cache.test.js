import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { CACHE_KEY, parseRecord, recordAfterCheck, serializeRecord } from '../lib/cache.js';

const here = dirname(fileURLToPath(import.meta.url));
const body = JSON.parse(readFileSync(join(here, '..', '..', 'fixtures', 'payload-reference.json'), 'utf8'));
const T0 = 1_792_600_000_000;

test('cache key is versioned', () => {
  assert.equal(CACHE_KEY, 'ww.payload.v1');
});

test('200 replaces the record; 304 only marks it checked', () => {
  const a = recordAfterCheck(null, { status: 200, etag: '"sha256-abc"', body, now: T0 });
  assert.deepEqual(a, { etag: '"sha256-abc"', body, savedAt: T0, lastChecked: T0, lastCheckOK: true });
  const b = recordAfterCheck(a, { status: 304, now: T0 + 1000 });
  assert.equal(b.body, body);
  assert.equal(b.etag, '"sha256-abc"');
  assert.equal(b.savedAt, T0, 'savedAt unchanged on 304');
  assert.equal(b.lastChecked, T0 + 1000);
  assert.equal(b.lastCheckOK, true);
  const c = recordAfterCheck(a, { status: 200, etag: '"sha256-def"', body: { ...body, hours: 44 }, now: T0 + 2000 });
  assert.equal(c.etag, '"sha256-def"');
  assert.equal(c.body.hours, 44);
  assert.equal(c.savedAt, T0 + 2000);
});

test('errors keep the cached body with lastCheckOK=false; nothing cached stays nothing', () => {
  const a = recordAfterCheck(null, { status: 200, etag: 'x', body, now: T0 });
  const off = recordAfterCheck(a, { status: 'error', now: T0 + 5000 });
  assert.equal(off.body, body);
  assert.equal(off.lastCheckOK, false);
  assert.equal(off.lastChecked, T0 + 5000);
  assert.equal(off.savedAt, T0);
  assert.equal(recordAfterCheck(a, { status: 503, now: T0 }).lastCheckOK, false);
  assert.equal(recordAfterCheck(null, { status: 'error', now: T0 }), null);
  assert.equal(recordAfterCheck(null, { status: 503, now: T0 }), null);
  assert.equal(recordAfterCheck(null, { status: 304, now: T0 }), null);
});

test('serialize / parse round-trips and rejects junk', () => {
  const a = recordAfterCheck(null, { status: 200, etag: '"e"', body, now: T0 });
  const back = parseRecord(serializeRecord(a));
  assert.deepEqual(back, a);
  assert.equal(parseRecord(null), null);
  assert.equal(parseRecord(''), null);
  assert.equal(parseRecord('not json'), null);
  assert.equal(parseRecord('{"etag":"e"}'), null);
  assert.equal(parseRecord(JSON.stringify({ ...a, body: { v: 2 } })), null);
  assert.equal(parseRecord(JSON.stringify({ ...a, savedAt: 'yesterday' })), null);
});
