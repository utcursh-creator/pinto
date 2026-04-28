// Tests for the 4-stage commenter filter. Uses an in-memory SQLite db so
// each test is isolated and fast.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'path';
import os from 'os';
import fs from 'fs/promises';
import { CommenterFilter } from '../src/filter.js';

function tempDbPath() {
  return path.join(os.tmpdir(), `filter-${Date.now()}-${Math.random().toString(36).slice(2)}.db`);
}

const noopLog = { info() {}, warn() {}, error() {} };

function makeCommenter(overrides = {}) {
  return {
    name: 'Jane Doe',
    profile_url: `https://www.linkedin.com/in/janedoe-${Math.random().toString(36).slice(2)}/`,
    headline: 'Founder | n8n automation consultant',
    comment_text: 'Great post',
    has_profile_image: true,
    source_post_url: 'https://www.linkedin.com/posts/x',
    scraped_at: new Date().toISOString(),
    ...overrides,
  };
}

test('rejects placeholder LinkedIn Member name', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([makeCommenter({ name: 'LinkedIn Member' })]);
  f.close();
  assert.equal(result.passed.length, 0);
  assert.equal(result.rejected.not_real, 1);
  await fs.rm(dbPath, { force: true });
});

test('rejects commenter without profile image', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([makeCommenter({ has_profile_image: false })]);
  f.close();
  assert.equal(result.passed.length, 0);
  assert.equal(result.rejected.not_real, 1);
  await fs.rm(dbPath, { force: true });
});

test('rejects commenter with hard-exclusion keyword in headline', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([makeCommenter({ headline: 'Recruiter at BigCo' })]);
  f.close();
  assert.equal(result.passed.length, 0);
  assert.equal(result.rejected.excluded, 1);
  await fs.rm(dbPath, { force: true });
});

test('rejects commenter with no ICP keywords', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([makeCommenter({ headline: 'Plumbing contractor in Texas' })]);
  f.close();
  assert.equal(result.passed.length, 0);
  assert.equal(result.rejected.no_keywords, 1);
  await fs.rm(dbPath, { force: true });
});

test('passes Segment 1 commenter with n8n in headline', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([makeCommenter({ headline: 'Founder | n8n automation builder' })]);
  f.close();
  assert.equal(result.passed.length, 1);
  assert.equal(result.passed[0].segment, 1);
  assert.ok(result.passed[0].filter_score >= 0.25);
  await fs.rm(dbPath, { force: true });
});

test('passes Segment 2 commenter with creator in headline', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([
    makeCommenter({ headline: 'AI educator | course creator | community builder' }),
  ]);
  f.close();
  assert.equal(result.passed.length, 1);
  assert.equal(result.passed[0].segment, 2);
  await fs.rm(dbPath, { force: true });
});

test('rejects duplicate commenter on second pass', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const c = makeCommenter({ headline: 'n8n automation founder' });
  const r1 = f.filter([c]);
  assert.equal(r1.passed.length, 1);
  const r2 = f.filter([c]);
  assert.equal(r2.passed.length, 0);
  assert.equal(r2.rejected.duplicate, 1);
  f.close();
  await fs.rm(dbPath, { force: true });
});

test('multiple commenters processed in batch with mixed outcomes', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([
    makeCommenter({ headline: 'n8n consultant founder' }), // pass seg 1
    makeCommenter({ name: 'LinkedIn Member' }), // not_real
    makeCommenter({ headline: 'Recruiter' }), // excluded
    makeCommenter({ headline: 'random plumber' }), // no_keywords
    makeCommenter({ headline: 'AI educator + course creator' }), // pass seg 2
  ]);
  f.close();
  assert.equal(result.passed.length, 2);
  assert.equal(result.rejected.not_real, 1);
  assert.equal(result.rejected.excluded, 1);
  assert.equal(result.rejected.no_keywords, 1);
  await fs.rm(dbPath, { force: true });
});

test('UiPath/Power Automate users are hard-excluded', async () => {
  const dbPath = tempDbPath();
  const f = new CommenterFilter(noopLog, dbPath);
  const result = f.filter([
    makeCommenter({ headline: 'UiPath developer + automation' }),
    makeCommenter({ headline: 'Power Automate consultant' }),
  ]);
  f.close();
  assert.equal(result.passed.length, 0);
  assert.equal(result.rejected.excluded, 2);
  await fs.rm(dbPath, { force: true });
});
