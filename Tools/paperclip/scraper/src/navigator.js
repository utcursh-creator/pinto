// Magnet picker. Selects which LinkedIn accounts to mine this cycle:
//   1. Loads magnet config
//   2. Drops any magnet currently in cooldown (3 days after last use)
//   3. Weights remaining by priority * expected_comment_quality
//   4. Returns the top N
//
// recordMagnetUse stamps each used magnet with a fresh 3-day cooldown and
// appends a history entry.

import fs from 'fs/promises';
import path from 'path';

const PRIORITY_WEIGHTS = { high: 3, medium: 2, low: 1 };
const COOLDOWN_MS = 3 * 24 * 60 * 60 * 1000; // 3 days

async function loadOrInitState(statePath) {
  try {
    return JSON.parse(await fs.readFile(statePath, 'utf8'));
  } catch {
    return { last_run: null, history: [], cooldown: {} };
  }
}

export async function pickMagnets(configPath, statePath, max) {
  const config = JSON.parse(await fs.readFile(configPath, 'utf8'));
  const state = await loadOrInitState(statePath);

  // Honor caller override, then config's max_per_cycle, then a safe default of 2.
  const effectiveMax = max ?? config.max_per_cycle ?? 2;

  // Flatten across both segments, tagging each with its segment number
  const allMagnets = [
    ...(config.magnets.segment_1_agencies || []).map((m) => ({ ...m, segment: 1 })),
    ...(config.magnets.segment_2_creators || []).map((m) => ({ ...m, segment: 2 })),
  ];

  const now = Date.now();
  const eligible = allMagnets.filter((m) => {
    const cooldownUntil = state.cooldown?.[m.id];
    if (!cooldownUntil) return true;
    return new Date(cooldownUntil).getTime() <= now;
  });

  if (eligible.length === 0) {
    throw new Error('All magnets in cooldown. Halting cycle.');
  }

  const weighted = eligible.map((m) => ({
    ...m,
    weight: (PRIORITY_WEIGHTS[m.priority] || 1) * (m.expected_comment_quality || 0.5),
  }));
  weighted.sort((a, b) => b.weight - a.weight);

  return weighted.slice(0, effectiveMax);
}

export async function recordMagnetUse(statePath, magnets, results) {
  const state = await loadOrInitState(statePath);
  const now = new Date();
  const cooldownUntil = new Date(now.getTime() + COOLDOWN_MS);

  for (const m of magnets) {
    state.cooldown[m.id] = cooldownUntil.toISOString();
  }
  state.history.push({
    date: now.toISOString(),
    magnets_used: magnets.map((m) => m.id),
    ...results,
  });
  state.last_run = now.toISOString();

  await fs.mkdir(path.dirname(statePath), { recursive: true });
  await fs.writeFile(statePath, JSON.stringify(state, null, 2));
}
