// Restriction detector + circuit breaker. The dummy account dies if we miss
// these signals — they MUST be checked after every navigation. Two severity
// levels:
//   hard: 999/429/403, /checkpoint/ URL, restriction text → 72h cooldown
//   soft: placeholder names rendering, throttling indicators → 24h cooldown
//         (but only after 2 in a single session, since one stray placeholder
//         can be incidental)
//
// The breaker file is the source of truth — index.js MUST check
// isBreakerOpen() before doing anything else.
//
// IMPORTANT TIMING NOTE: checkPageContent waits for SPA hydration before
// reading body text. LinkedIn is a heavy React SPA — at domcontentloaded the
// shell HTML is present but feed cards, restriction banners, and "LinkedIn
// Member" placeholders haven't been injected yet. Reading body.textContent
// too early returns shell-only text and the detector goes blind to soft
// signals and JS-injected restriction banners.

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_BREAKER_PATH = path.join(__dirname, '..', 'state', 'circuit-breaker.json');

// HARD signals: immediate halt + 72h cooldown
const HARD_RESTRICTION_PATHS = [
  '/uas/login',
  '/checkpoint/challenge',
  '/checkpoint/lg/login-submit',
  '/authwall',
];

const HARD_RESTRICTION_TEXTS = [
  "we've restricted your account",
  'temporarily restricted',
  'unusual login activity',
  'verify you',
  'security verification',
  'reached the commercial use limit',
  'commercial use limit',
];

const HARD_HTTP_STATUSES = new Set([999, 429, 403]);

// Sentinels that indicate LinkedIn's React tree has hydrated. Race them in
// order — the first one to become visible wins. These are intentionally
// CONTENT-rendered selectors, not shell elements like <main>, because we
// need to know dynamic content has actually been injected before reading
// body.textContent.
const HYDRATION_SENTINELS = [
  'div.feed-shared-update-v2',           // feed card (on /feed/ and activity pages)
  'article.comments-comment-entity',      // comment article (on post pages)
  'main.scaffold-finite-scroll',          // scrollable feed container
  'div.scaffold-layout__main',            // generic logged-in layout main
  'section.artdeco-card',                 // any artdeco card (broad fallback)
];

// Wait for ANY hydration sentinel up to maxMs total. Returns the matching
// selector string, or null if nothing matched (caller falls back to a fixed
// dwell so JS-injected banners can still land).
async function waitForHydration(page, maxMs = 5000) {
  const start = Date.now();
  for (const sel of HYDRATION_SENTINELS) {
    const remaining = Math.max(0, maxMs - (Date.now() - start));
    if (remaining < 200) break;
    const matched = await page
      .locator(sel)
      .first()
      .waitFor({ state: 'visible', timeout: Math.min(remaining, 1500) })
      .then(() => true)
      .catch(() => false);
    if (matched) return sel;
  }
  return null;
}

export class RestrictionDetector {
  constructor(log, breakerPath = DEFAULT_BREAKER_PATH, { skipHydrationWait = false } = {}) {
    this.log = log;
    this.breakerPath = breakerPath;
    this.softHitsThisSession = 0;
    // Tests pass skipHydrationWait: true to bypass waitForHydration since
    // mock pages don't simulate Playwright locators perfectly. Production
    // code never sets this.
    this.skipHydrationWait = skipHydrationWait;
  }

  async checkResponseStatus(response, url) {
    if (!response) return { ok: true };
    const status = response.status();
    if (HARD_HTTP_STATUSES.has(status)) {
      return {
        ok: false,
        severity: 'hard',
        reason: `HTTP ${status} on ${url}`,
      };
    }
    return { ok: true };
  }

  async checkPageContent(page) {
    const url = page.url();

    // Hard URL check first — fast, no waiting needed
    for (const fragment of HARD_RESTRICTION_PATHS) {
      if (url.includes(fragment)) {
        return {
          ok: false,
          severity: 'hard',
          reason: `Redirected to restriction URL: ${url}`,
        };
      }
    }

    // Wait for SPA hydration before reading body text. The body.textContent
    // check below would otherwise read shell-only HTML and miss everything
    // injected by React after domcontentloaded. If no sentinel matches (e.g.
    // on a restriction page where normal content never renders), we still
    // dwell briefly so JS-injected banners can land.
    if (!this.skipHydrationWait) {
      const sentinel = await waitForHydration(page, 5000);
      if (!sentinel) {
        await page.waitForTimeout(1500).catch(() => {});
      }
    }

    // Hard text check on page body
    let bodyText = '';
    try {
      bodyText = (await page.locator('body').textContent({ timeout: 3000 })) || '';
    } catch {
      // Page might be navigating; treat as no text
    }
    const lowerBody = bodyText.toLowerCase();
    for (const phrase of HARD_RESTRICTION_TEXTS) {
      if (lowerBody.includes(phrase)) {
        return {
          ok: false,
          severity: 'hard',
          reason: `Restriction text found: "${phrase}"`,
        };
      }
    }

    // Soft signal: count placeholder names in visible content. One stray
    // "LinkedIn Member" can happen on legitimate posts (deleted accounts);
    // a wave of them means we're being throttled.
    const placeholderCount = (bodyText.match(/LinkedIn Member/g) || []).length;
    if (placeholderCount > 5) {
      this.softHitsThisSession++;
      this.log.warn(
        `Soft signal: ${placeholderCount} 'LinkedIn Member' placeholders detected (soft hit ${this.softHitsThisSession} this session)`
      );

      if (this.softHitsThisSession >= 2) {
        return {
          ok: false,
          severity: 'soft',
          reason: '2+ soft signals in single session',
        };
      }
    }

    return { ok: true };
  }

  async tripBreaker(severity, reason) {
    const cooldownHours = severity === 'hard' ? 72 : 24;
    const trippedAt = new Date();
    const cooldownUntil = new Date(trippedAt.getTime() + cooldownHours * 60 * 60 * 1000);

    const state = {
      tripped_at: trippedAt.toISOString(),
      severity,
      reason,
      cooldown_until: cooldownUntil.toISOString(),
    };

    await fs.mkdir(path.dirname(this.breakerPath), { recursive: true });
    await fs.writeFile(this.breakerPath, JSON.stringify(state, null, 2));
    this.log.error(
      `CIRCUIT BREAKER TRIPPED [${severity}]: ${reason}. Cooldown until ${cooldownUntil.toISOString()}`
    );
  }

  async isBreakerOpen() {
    try {
      const text = await fs.readFile(this.breakerPath, 'utf8');
      const state = JSON.parse(text);
      const cooldownUntil = new Date(state.cooldown_until);
      if (cooldownUntil > new Date()) {
        return { open: true, until: cooldownUntil, reason: state.reason, severity: state.severity };
      }
    } catch {
      // Missing file or parse error = no breaker active
    }
    return { open: false };
  }
}
