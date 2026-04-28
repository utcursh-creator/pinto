// Hard rate limit enforcer. These limits are calibrated for SKIP-WARMUP mode
// (week 1) where the dummy account has no automation history. They protect
// the account from getting flagged. NEVER raise these without explicit
// approval — the cost of a banned dummy is days of cooldown and a manual
// re-create.
//
// State is persisted to JSON so counters survive process restarts.

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_COUNTER_PATH = path.join(__dirname, '..', 'state', 'rate-counters.json');

// SKIP-WARMUP mode (week 1): ULTRA conservative. These are production limits
// per the plan. DO NOT raise without explicit user approval. Any temporary
// task-specific bumps should be reverted to these values once the task
// completes. Task 17 verification is complete; limits restored to plan values.
export const LIMITS = Object.freeze({
  page_loads_per_hour: 6,
  page_loads_per_day: 10,
  page_loads_per_week: 50,
  sessions_per_day: 1,
  session_min_minutes: 25,
  session_max_minutes: 40,
});

function emptyCounters() {
  return { hourly: {}, daily: {}, weekly: {}, sessions_today: 0, last_session_date: null };
}

function getWeekKey(date) {
  // ISO-ish week key: anchor on the Sunday of the week
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - d.getDay());
  return d.toISOString().slice(0, 10);
}

export class RateLimiter {
  constructor(log, counterPath = DEFAULT_COUNTER_PATH) {
    this.log = log;
    this.counterPath = counterPath;
  }

  async loadCounters() {
    try {
      const text = await fs.readFile(this.counterPath, 'utf8');
      return JSON.parse(text);
    } catch {
      return emptyCounters();
    }
  }

  async saveCounters(counters) {
    await fs.mkdir(path.dirname(this.counterPath), { recursive: true });
    await fs.writeFile(this.counterPath, JSON.stringify(counters, null, 2));
  }

  async canLoadPage() {
    const counters = await this.loadCounters();
    const now = new Date();
    const hourKey = now.toISOString().slice(0, 13); // YYYY-MM-DDTHH
    const dayKey = now.toISOString().slice(0, 10);  // YYYY-MM-DD
    const weekKey = getWeekKey(now);

    const hourly = counters.hourly[hourKey] || 0;
    const daily = counters.daily[dayKey] || 0;
    const weekly = counters.weekly[weekKey] || 0;

    if (hourly >= LIMITS.page_loads_per_hour) {
      return { ok: false, reason: `Hourly limit reached (${hourly}/${LIMITS.page_loads_per_hour})` };
    }
    if (daily >= LIMITS.page_loads_per_day) {
      return { ok: false, reason: `Daily limit reached (${daily}/${LIMITS.page_loads_per_day})` };
    }
    if (weekly >= LIMITS.page_loads_per_week) {
      return { ok: false, reason: `Weekly limit reached (${weekly}/${LIMITS.page_loads_per_week})` };
    }
    return { ok: true };
  }

  async canStartSession() {
    const counters = await this.loadCounters();
    const today = new Date().toISOString().slice(0, 10);
    if (counters.last_session_date === today && counters.sessions_today >= LIMITS.sessions_per_day) {
      return {
        ok: false,
        reason: `Session limit for today reached (${counters.sessions_today}/${LIMITS.sessions_per_day})`,
      };
    }
    return { ok: true };
  }

  async recordPageLoad() {
    const counters = await this.loadCounters();
    const now = new Date();
    const hourKey = now.toISOString().slice(0, 13);
    const dayKey = now.toISOString().slice(0, 10);
    const weekKey = getWeekKey(now);
    counters.hourly[hourKey] = (counters.hourly[hourKey] || 0) + 1;
    counters.daily[dayKey] = (counters.daily[dayKey] || 0) + 1;
    counters.weekly[weekKey] = (counters.weekly[weekKey] || 0) + 1;
    await this.saveCounters(counters);
  }

  async recordSessionStart() {
    const counters = await this.loadCounters();
    const today = new Date().toISOString().slice(0, 10);
    if (counters.last_session_date !== today) {
      counters.sessions_today = 0;
    }
    counters.sessions_today += 1;
    counters.last_session_date = today;
    await this.saveCounters(counters);
  }
}
