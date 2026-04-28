// Tests for rate-limiter. Uses node:test. Each test gets a fresh temp counter
// path so state never leaks between tests.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { RateLimiter, LIMITS } from '../src/rate-limiter.js';

function tempCounterPath() {
  return path.join(os.tmpdir(), `rate-counters-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
}

const noopLog = { info() {}, warn() {}, error() {} };

test('canLoadPage returns ok when no counters exist', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  const result = await limiter.canLoadPage();
  assert.equal(result.ok, true);
  await fs.rm(counterPath, { force: true });
});

test('canLoadPage blocks once daily limit reached', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  // Seed state directly to verify the daily check fires independently of
  // the hourly check (filling daily via recordPageLoad would hit hourly first).
  const now = new Date();
  const dayKey = now.toISOString().slice(0, 10);
  const weekStart = new Date(now);
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(weekStart.getDate() - weekStart.getDay());
  const weekKey = weekStart.toISOString().slice(0, 10);
  await fs.mkdir(path.dirname(counterPath), { recursive: true });
  await fs.writeFile(
    counterPath,
    JSON.stringify({
      hourly: {},
      daily: { [dayKey]: LIMITS.page_loads_per_day },
      weekly: { [weekKey]: LIMITS.page_loads_per_day },
      sessions_today: 0,
      last_session_date: null,
    })
  );
  const result = await limiter.canLoadPage();
  assert.equal(result.ok, false);
  assert.match(result.reason, /[Dd]aily/);
  await fs.rm(counterPath, { force: true });
});

test('canLoadPage blocks once hourly limit reached', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  for (let i = 0; i < LIMITS.page_loads_per_hour; i++) {
    await limiter.recordPageLoad();
  }
  const result = await limiter.canLoadPage();
  assert.equal(result.ok, false);
  assert.match(result.reason, /[Hh]ourly/);
  await fs.rm(counterPath, { force: true });
});

test('canStartSession blocks once sessions_per_day reached', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  for (let i = 0; i < LIMITS.sessions_per_day; i++) {
    await limiter.recordSessionStart();
  }
  const result = await limiter.canStartSession();
  assert.equal(result.ok, false);
  assert.match(result.reason, /[Ss]ession/);
  await fs.rm(counterPath, { force: true });
});

test('recordPageLoad increments hourly, daily, and weekly counters', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  await limiter.recordPageLoad();
  await limiter.recordPageLoad();
  const counters = await limiter.loadCounters();
  const dayKey = new Date().toISOString().slice(0, 10);
  assert.equal(counters.daily[dayKey], 2);
  await fs.rm(counterPath, { force: true });
});

test('sessions_today resets when last_session_date is yesterday', async () => {
  const counterPath = tempCounterPath();
  const limiter = new RateLimiter(noopLog, counterPath);
  // Manually write a stale state
  await fs.writeFile(
    counterPath,
    JSON.stringify({
      hourly: {},
      daily: {},
      weekly: {},
      sessions_today: 99,
      last_session_date: '2020-01-01',
    })
  );
  await limiter.recordSessionStart();
  const counters = await limiter.loadCounters();
  assert.equal(counters.sessions_today, 1);
  await fs.rm(counterPath, { force: true });
});
