// Tests for the magnet picker. Pure logic — no browser involved.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { pickMagnets, recordMagnetUse } from '../src/navigator.js';

function tempPath(suffix) {
  return path.join(os.tmpdir(), `magnet-${suffix}-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
}

const sampleConfig = {
  version: 1,
  magnets: {
    segment_1_agencies: [
      { id: 'a', name: 'A', linkedin_url: 'https://x/a', priority: 'high', expected_comment_quality: 0.6 },
      { id: 'b', name: 'B', linkedin_url: 'https://x/b', priority: 'medium', expected_comment_quality: 0.5 },
      { id: 'c', name: 'C', linkedin_url: 'https://x/c', priority: 'low', expected_comment_quality: 0.3 },
    ],
    segment_2_creators: [
      { id: 'd', name: 'D', linkedin_url: 'https://x/d', priority: 'high', expected_comment_quality: 0.7 },
    ],
  },
};

async function writeConfig(p) {
  await fs.writeFile(p, JSON.stringify(sampleConfig));
}

test('pickMagnets returns up to max magnets', async () => {
  const cfgPath = tempPath('cfg');
  const statePath = tempPath('state');
  await writeConfig(cfgPath);
  const picked = await pickMagnets(cfgPath, statePath, 2);
  assert.equal(picked.length, 2);
  await fs.rm(cfgPath, { force: true });
});

test('pickMagnets prioritizes high-priority high-quality magnets', async () => {
  const cfgPath = tempPath('cfg');
  const statePath = tempPath('state');
  await writeConfig(cfgPath);
  const picked = await pickMagnets(cfgPath, statePath, 1);
  // 'd' has highest weight (priority high * 0.7), should win over 'a' (high * 0.6)
  assert.equal(picked[0].id, 'd');
  await fs.rm(cfgPath, { force: true });
});

test('pickMagnets excludes magnets in cooldown', async () => {
  const cfgPath = tempPath('cfg');
  const statePath = tempPath('state');
  await writeConfig(cfgPath);
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  await fs.writeFile(
    statePath,
    JSON.stringify({ last_run: null, history: [], cooldown: { d: future, a: future } })
  );
  const picked = await pickMagnets(cfgPath, statePath, 4);
  const ids = picked.map((m) => m.id);
  assert.ok(!ids.includes('d'), 'd should be in cooldown');
  assert.ok(!ids.includes('a'), 'a should be in cooldown');
  assert.ok(ids.includes('b'));
  assert.ok(ids.includes('c'));
  await fs.rm(cfgPath, { force: true });
  await fs.rm(statePath, { force: true });
});

test('pickMagnets throws when all magnets in cooldown', async () => {
  const cfgPath = tempPath('cfg');
  const statePath = tempPath('state');
  await writeConfig(cfgPath);
  const future = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  await fs.writeFile(
    statePath,
    JSON.stringify({
      last_run: null,
      history: [],
      cooldown: { a: future, b: future, c: future, d: future },
    })
  );
  await assert.rejects(() => pickMagnets(cfgPath, statePath, 2), /cooldown/i);
  await fs.rm(cfgPath, { force: true });
  await fs.rm(statePath, { force: true });
});

test('pickMagnets ignores expired cooldowns', async () => {
  const cfgPath = tempPath('cfg');
  const statePath = tempPath('state');
  await writeConfig(cfgPath);
  const past = new Date(Date.now() - 1000).toISOString();
  await fs.writeFile(
    statePath,
    JSON.stringify({ last_run: null, history: [], cooldown: { d: past } })
  );
  const picked = await pickMagnets(cfgPath, statePath, 1);
  assert.equal(picked[0].id, 'd', 'expired cooldown should not exclude d');
  await fs.rm(cfgPath, { force: true });
  await fs.rm(statePath, { force: true });
});

test('recordMagnetUse writes 3-day cooldown for each used magnet', async () => {
  const statePath = tempPath('state');
  const used = [{ id: 'a' }, { id: 'b' }];
  await recordMagnetUse(statePath, used, { commenters_extracted: 10, commenters_passed_filter: 4 });
  const state = JSON.parse(await fs.readFile(statePath, 'utf8'));
  assert.ok(state.cooldown.a);
  assert.ok(state.cooldown.b);
  const cooldownMs = new Date(state.cooldown.a).getTime() - Date.now();
  // ~3 days, allow 5s drift
  assert.ok(cooldownMs > 3 * 24 * 60 * 60 * 1000 - 5000);
  assert.ok(cooldownMs < 3 * 24 * 60 * 60 * 1000 + 5000);
  assert.equal(state.history.length, 1);
  await fs.rm(statePath, { force: true });
});
