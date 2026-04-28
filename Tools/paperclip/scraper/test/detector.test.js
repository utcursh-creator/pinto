// Tests for the restriction detector. Most logic is pure (URL string checks,
// HTTP status code mapping, breaker file persistence). checkPageContent is
// tested against a mock Page that stubs only the methods the detector touches
// (page.url(), page.locator('body').textContent(), page.waitForTimeout()).
// We pass skipHydrationWait:true in the constructor so the hydration sentinel
// race is bypassed — mock locators can't simulate Playwright's waitFor state
// machine, and the timing shim is covered by the test-detection smoke script.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { RestrictionDetector } from '../src/detector.js';

function tempBreakerPath() {
  return path.join(os.tmpdir(), `circuit-breaker-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
}

const noopLog = { info() {}, warn() {}, error() {} };

// Minimal Page stub for checkPageContent tests. Only page.url() and the
// body locator's textContent() need to be honest — the rest is no-op.
function mockPage({ url = 'https://www.linkedin.com/feed/', body = '' } = {}) {
  return {
    url: () => url,
    locator: (selector) => ({
      first: () => ({
        textContent: async () => (selector === 'body' ? body : ''),
        waitFor: async () => {
          // Should never be called with skipHydrationWait:true
          throw new Error('mock page: hydration wait should be skipped in tests');
        },
      }),
      textContent: async () => (selector === 'body' ? body : ''),
    }),
    waitForTimeout: async () => {},
  };
}

function makeTestDetector() {
  return new RestrictionDetector(noopLog, tempBreakerPath(), { skipHydrationWait: true });
}

test('checkResponseStatus passes on null response', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const result = await d.checkResponseStatus(null, 'https://x.test');
  assert.equal(result.ok, true);
});

test('checkResponseStatus passes on 200', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const fakeResponse = { status: () => 200 };
  const result = await d.checkResponseStatus(fakeResponse, 'https://x.test');
  assert.equal(result.ok, true);
});

test('checkResponseStatus fails on 999 with hard severity', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const fakeResponse = { status: () => 999 };
  const result = await d.checkResponseStatus(fakeResponse, 'https://x.test');
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /999/);
});

test('checkResponseStatus fails on 429 with hard severity', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const fakeResponse = { status: () => 429 };
  const result = await d.checkResponseStatus(fakeResponse, 'https://x.test');
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
});

test('checkResponseStatus fails on 403 with hard severity', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const fakeResponse = { status: () => 403 };
  const result = await d.checkResponseStatus(fakeResponse, 'https://x.test');
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
});

test('tripBreaker writes file with hard severity and 72h cooldown', async () => {
  const breakerPath = tempBreakerPath();
  const d = new RestrictionDetector(noopLog, breakerPath);
  await d.tripBreaker('hard', 'test-reason');
  const state = JSON.parse(await fs.readFile(breakerPath, 'utf8'));
  assert.equal(state.severity, 'hard');
  assert.equal(state.reason, 'test-reason');
  const cooldownMs = new Date(state.cooldown_until).getTime() - new Date(state.tripped_at).getTime();
  // Allow 1s drift for clock skew
  assert.ok(cooldownMs >= 72 * 60 * 60 * 1000 - 1000);
  assert.ok(cooldownMs <= 72 * 60 * 60 * 1000 + 1000);
  await fs.rm(breakerPath, { force: true });
});

test('tripBreaker writes file with soft severity and 24h cooldown', async () => {
  const breakerPath = tempBreakerPath();
  const d = new RestrictionDetector(noopLog, breakerPath);
  await d.tripBreaker('soft', 'soft-test');
  const state = JSON.parse(await fs.readFile(breakerPath, 'utf8'));
  assert.equal(state.severity, 'soft');
  const cooldownMs = new Date(state.cooldown_until).getTime() - new Date(state.tripped_at).getTime();
  assert.ok(cooldownMs >= 24 * 60 * 60 * 1000 - 1000);
  assert.ok(cooldownMs <= 24 * 60 * 60 * 1000 + 1000);
  await fs.rm(breakerPath, { force: true });
});

test('isBreakerOpen returns false when no breaker file exists', async () => {
  const d = new RestrictionDetector(noopLog, tempBreakerPath());
  const result = await d.isBreakerOpen();
  assert.equal(result.open, false);
});

test('isBreakerOpen returns true within cooldown window', async () => {
  const breakerPath = tempBreakerPath();
  const d = new RestrictionDetector(noopLog, breakerPath);
  await d.tripBreaker('hard', 'still-cooling');
  const result = await d.isBreakerOpen();
  assert.equal(result.open, true);
  assert.equal(result.reason, 'still-cooling');
  await fs.rm(breakerPath, { force: true });
});

test('isBreakerOpen returns false after cooldown expires', async () => {
  const breakerPath = tempBreakerPath();
  const d = new RestrictionDetector(noopLog, breakerPath);
  // Write an expired breaker manually
  await fs.writeFile(
    breakerPath,
    JSON.stringify({
      tripped_at: new Date('2020-01-01').toISOString(),
      severity: 'hard',
      reason: 'expired',
      cooldown_until: new Date('2020-01-04').toISOString(),
    })
  );
  const result = await d.isBreakerOpen();
  assert.equal(result.open, false);
  await fs.rm(breakerPath, { force: true });
});

// ---- checkPageContent negative + positive cases ----

test('checkPageContent passes on a healthy feed page', async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/feed/',
    body: 'Jane Doe posted an update about n8n. Like Comment Share.',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, true);
});

test('checkPageContent fails on /checkpoint/challenge URL with hard severity', async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/checkpoint/challenge/verify',
    body: 'security verification',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /checkpoint/);
});

test('checkPageContent fails on /authwall URL with hard severity', async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/authwall?trk=gf',
    body: '',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /authwall/);
});

test('checkPageContent fails on /uas/login URL with hard severity', async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/uas/login?session_redirect=/feed/',
    body: '',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /uas\/login/);
});

test("checkPageContent fails on 'we've restricted your account' text", async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/feed/',
    body: "We've restricted your account. Please verify your identity.",
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /restricted your account/i);
});

test("checkPageContent fails on 'temporarily restricted' text", async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/feed/',
    body: 'Your account has been temporarily restricted due to unusual activity.',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
  assert.match(result.reason, /temporarily restricted/i);
});

test("checkPageContent fails on 'commercial use limit' text", async () => {
  const d = makeTestDetector();
  const page = mockPage({
    url: 'https://www.linkedin.com/search/results/people/',
    body: 'You have reached the commercial use limit for this month.',
  });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, false);
  assert.equal(result.severity, 'hard');
});

test('checkPageContent does NOT fire soft signal when placeholder count is low', async () => {
  const d = makeTestDetector();
  // 3 placeholders — below the >5 threshold
  const body = 'LinkedIn Member commented. LinkedIn Member liked. LinkedIn Member shared.';
  const page = mockPage({ url: 'https://www.linkedin.com/feed/', body });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, true);
  assert.equal(d.softHitsThisSession, 0);
});

test('checkPageContent records but does not fail on first soft signal', async () => {
  const d = makeTestDetector();
  // 6 placeholders — above threshold, but first hit shouldn't trip breaker
  const body = Array(6).fill('LinkedIn Member commented.').join(' ');
  const page = mockPage({ url: 'https://www.linkedin.com/feed/', body });
  const result = await d.checkPageContent(page);
  assert.equal(result.ok, true);
  assert.equal(d.softHitsThisSession, 1);
});

test('checkPageContent fails on second soft signal within same session', async () => {
  const d = makeTestDetector();
  const body = Array(6).fill('LinkedIn Member commented.').join(' ');
  const page = mockPage({ url: 'https://www.linkedin.com/feed/', body });
  const first = await d.checkPageContent(page);
  assert.equal(first.ok, true);
  const second = await d.checkPageContent(page);
  assert.equal(second.ok, false);
  assert.equal(second.severity, 'soft');
  assert.match(second.reason, /soft signals/i);
});
