#!/usr/bin/env node
// ghost-cursor-playwright ships a `console.log('rand')` debug statement inside
// its random-value helper (cursor.js:199). It fires on every Bezier curve
// point generation, flooding stdout with literal "rand" lines. Patch the stock
// console.log to drop this exact string before any library imports run.
// Everything else is passed through untouched.
const __origConsoleLog = console.log.bind(console);
console.log = (...args) => {
  if (args.length === 1 && args[0] === 'rand') return;
  __origConsoleLog(...args);
};

// Entry point. Orchestrates the four operational modes:
//   --mode=login           manual interactive login (writes persistent context)
//   --mode=health          quick "is the session still alive?" check
//   --mode=test-detection  open feed only, run detector against the rendered page
//   --mode=scrape          full mining cycle (default)
//
// Exit codes (must stay stable; the Paperclip Scraper agent reads these):
//   0  success
//   1  unexpected error
//   97 not logged in
//   98 rate limit reached
//   99 circuit breaker tripped or restriction signal

import { launchBrowser } from './browser.js';
import { isLoggedIn, manualLogin } from './auth.js';
import { pickMagnets, recordMagnetUse } from './navigator.js';
import {
  extractCommentsFromPost,
  extractRecentPostUrls,
  captureActivityPageSnapshot,
} from './extractor.js';
import { CommenterFilter } from './filter.js';
import { RestrictionDetector } from './detector.js';
import { Humanizer } from './humanize.js';
import { RateLimiter } from './rate-limiter.js';
import { writeOutput } from './storage.js';
import { createLogger } from './logger.js';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.join(__dirname, '..', 'config', 'magnet-accounts.json');
const STATE_DIR = path.join(__dirname, '..', 'state');
const ROTATION_PATH = path.join(STATE_DIR, 'magnet-rotation.json');
const RATE_COUNTERS_PATH = path.join(STATE_DIR, 'rate-counters.json');
const BREAKER_PATH = path.join(STATE_DIR, 'circuit-breaker.json');

// Defensive unhandledRejection filter. ghost-cursor-playwright's mouse-helper
// and some Playwright frame/navigation listeners can leak "Execution context
// was destroyed" rejections during navigation — these are benign races in
// helper code that isn't part of our scraping control flow. We swallow those
// specifically so one cosmetic race doesn't crash the whole scrape. Any other
// unhandled rejection is re-thrown so real bugs still surface.
process.on('unhandledRejection', (reason) => {
  const msg = (reason && reason.message) || String(reason);
  const benign =
    msg.includes('Execution context was destroyed') ||
    msg.includes('Target closed') ||
    msg.includes('Target page, context or browser has been closed');
  if (benign) {
    process.stderr.write(`[WARN] Swallowed benign async rejection: ${msg}\n`);
    return;
  }
  throw reason;
});

// Read a state file and parse it; return null if missing or unreadable. Used
// by the post-run summary — we never want the summary to crash a successful
// scrape just because a state file was deleted mid-flight.
async function readStateFile(p) {
  try {
    return JSON.parse(await fs.readFile(p, 'utf8'));
  } catch {
    return null;
  }
}

// Compact post-scrape summary. Logs today's rate counter usage, which magnets
// are now on cooldown, and whether a breaker file exists. Operators should be
// able to read one log line and know "are we safe, how much budget is left,
// what's cooling down" without cat-ing three JSON files.
async function logStateSummary(log) {
  const counters = await readStateFile(RATE_COUNTERS_PATH);
  const rotation = await readStateFile(ROTATION_PATH);
  const breaker = await readStateFile(BREAKER_PATH);

  const today = new Date().toISOString().slice(0, 10);
  const hourKey = new Date().toISOString().slice(0, 13);

  const dailyLoads = counters?.daily?.[today] ?? 0;
  const hourlyLoads = counters?.hourly?.[hourKey] ?? 0;
  const sessionsToday =
    counters?.last_session_date === today ? counters?.sessions_today ?? 0 : 0;

  const cooldownEntries = Object.entries(rotation?.cooldown ?? {})
    .filter(([, until]) => new Date(until) > new Date())
    .map(([id, until]) => `${id}→${until.slice(0, 10)}`);

  log.info(
    `State summary: page_loads today=${dailyLoads} hour=${hourlyLoads}, sessions_today=${sessionsToday}, magnet_cooldowns=[${cooldownEntries.join(', ')}], breaker=${
      breaker ? `OPEN (${breaker.severity}, until ${breaker.cooldown_until})` : 'closed'
    }`
  );
}

function parseArgs(argv) {
  const args = {};
  for (const a of argv) {
    if (!a.startsWith('--')) continue;
    const [k, v] = a.replace(/^--/, '').split('=');
    args[k] = v ?? true;
  }
  return args;
}

function buildSessionId() {
  return `scrape-${new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)}`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const mode = args.mode || 'scrape';
  const sessionId = buildSessionId();
  const log = await createLogger(sessionId);
  log.info(`Starting Scraper [mode=${mode}, session=${sessionId}]`);

  // Pre-flight 1: circuit breaker
  const detector = new RestrictionDetector(log);
  const breaker = await detector.isBreakerOpen();
  if (breaker.open) {
    log.error(
      `Circuit breaker OPEN [${breaker.severity}] until ${breaker.until.toISOString()}: ${breaker.reason}`
    );
    process.exit(99);
  }

  // Pre-flight 2: rate limiter (only enforced for scrape mode)
  const limiter = new RateLimiter(log);
  if (mode === 'scrape') {
    const sessionCheck = await limiter.canStartSession();
    if (!sessionCheck.ok) {
      log.error(`Cannot start session: ${sessionCheck.reason}`);
      process.exit(98);
    }
  }

  // Launch browser. Headed in production — never run headless on the dummy.
  await log.info('Launching browser...');
  const context = await launchBrowser({ headless: false });
  await log.info(`Browser launched, pages=${context.pages().length}`);
  const page = context.pages()[0] || (await context.newPage());
  await log.info('Page ready');

  try {
    // ─── MODE: login ────────────────────────────────────────────────────────
    if (mode === 'login') {
      await manualLogin(page, log);
      log.info('Login complete. Persistent context saved.');
      return;
    }

    // ─── MODE: health ───────────────────────────────────────────────────────
    if (mode === 'health') {
      let status;
      try {
        status = await isLoggedIn(page);
      } catch (e) {
        await log.error(`isLoggedIn threw: ${e?.stack || e}`);
        process.exitCode = 97;
        return;
      }
      // Awaiting log.info is required — createLogger writes via fs.appendFile
      // and the health mode exits immediately after this line. Without the
      // await the promise is dropped when process.exitCode triggers the exit.
      await log.info(
        `Health check: loggedIn=${status.loggedIn}, restricted=${status.restricted}, url=${status.finalUrl || 'n/a'}`
      );
      if (!status.loggedIn) {
        await log.warn(
          `Diagnostic: title=${JSON.stringify(status.title)}, bodyLength=${status.bodyLength}, httpStatus=${status.httpStatus}`
        );
        if (status.bodyPreview) {
          await log.warn(`Body preview: ${status.bodyPreview}`);
        }
        process.exitCode = 97;
      }
      return;
    }

    // ─── MODE: test-detection ───────────────────────────────────────────────
    if (mode === 'test-detection') {
      log.info('Test-detection: visiting feed and running detector');
      const status = await isLoggedIn(page);
      if (!status.loggedIn) {
        if (status.restricted) {
          await detector.tripBreaker('hard', 'Restricted on test-detection login check');
          process.exit(99);
        }
        log.error('Not logged in. Run --mode=login first.');
        process.exit(97);
      }
      const contentCheck = await detector.checkPageContent(page);
      if (!contentCheck.ok) {
        await detector.tripBreaker(contentCheck.severity, contentCheck.reason);
        process.exit(99);
      }
      log.info('Test-detection: no restriction signals fired');
      return;
    }

    // ─── MODE: scrape (default) ─────────────────────────────────────────────

    // Verify session before doing anything else
    const status = await isLoggedIn(page);
    if (!status.loggedIn) {
      if (status.restricted) {
        await detector.tripBreaker('hard', 'Restricted on session login check');
        process.exit(99);
      }
      log.error('Not logged in. Run with --mode=login to authenticate.');
      process.exit(97);
    }

    // Initialize humanizer + record session start
    const humanize = new Humanizer(page);
    await humanize.init();
    await limiter.recordSessionStart();

    // Warm-up: feed → notifications → mynetwork. Looks like a normal user.
    await humanize.warmupSession(log);

    // Pick which magnet accounts to mine this cycle. Max comes from
    // config.max_per_cycle (no caller override here).
    const magnets = await pickMagnets(CONFIG_PATH, ROTATION_PATH);
    log.info(`Picked magnets: ${magnets.map((m) => m.id).join(', ')}`);

    const allCommenters = [];
    let postsVisited = 0;

    for (const magnet of magnets) {
      // Rate limit gate before navigating to a magnet's activity feed
      const canLoad = await limiter.canLoadPage();
      if (!canLoad.ok) {
        log.warn(`Stopping early: ${canLoad.reason}`);
        break;
      }

      const activityUrl = `${magnet.linkedin_url}recent-activity/all/`;
      log.info(`Navigating to magnet activity: ${activityUrl}`);
      let response;
      try {
        // safeGoto wraps page.goto in a hard Promise.race timeout so a dead
        // CDP session can't hang the scraper. Returns null on timeout.
        response = await humanize.safeGoto(activityUrl, { timeoutMs: 35000 });
      } catch (e) {
        log.warn(`Failed to navigate to ${activityUrl}: ${e.message}`);
        continue;
      }
      await limiter.recordPageLoad();

      // Detection check after the navigation
      const respCheck = await detector.checkResponseStatus(response, activityUrl);
      if (!respCheck.ok) {
        await detector.tripBreaker(respCheck.severity, respCheck.reason);
        process.exit(99);
      }
      const contentCheck = await detector.checkPageContent(page);
      if (!contentCheck.ok) {
        await detector.tripBreaker(contentCheck.severity, contentCheck.reason);
        process.exit(99);
      }

      await humanize.dwell(5000, 9000);
      await humanize.scroll('down', 5);
      // Extra scroll to trigger the activity feed's lazy pagination, then a
      // beat for new posts to hydrate before we query them.
      await humanize.scroll('down', 4);
      await humanize.dwell(2500, 4500);

      // Pull up to 2 post URLs from this magnet's recent activity
      const postLinks = await extractRecentPostUrls(page, 2);
      log.info(`Found ${postLinks.length} post URLs for ${magnet.id}`);

      // Zero results are suspicious — capture a snapshot so the operator can
      // diagnose (login wall? selector drift? empty feed? hidden profile?).
      if (postLinks.length === 0) {
        const snap = await captureActivityPageSnapshot(page);
        log.warn(
          `Zero post URLs for ${magnet.id}. url=${snap.url} title=${JSON.stringify(
            snap.title
          )} bodyLength=${snap.bodyLength} looseActivityLinks=${snap.looseLinkCount}`
        );
        if (snap.bodyPreview) {
          log.warn(`Activity page body preview: ${snap.bodyPreview}`);
        }
      }

      for (const postUrl of postLinks) {
        const canLoadAgain = await limiter.canLoadPage();
        if (!canLoadAgain.ok) {
          log.warn(`Stopping post loop: ${canLoadAgain.reason}`);
          break;
        }

        try {
          const comments = await extractCommentsFromPost(page, postUrl, humanize, log);
          await limiter.recordPageLoad();

          // Detection check after each post
          const postCheck = await detector.checkPageContent(page);
          if (!postCheck.ok) {
            await detector.tripBreaker(postCheck.severity, postCheck.reason);
            process.exit(99);
          }

          // Tag with magnet source so the BDR can credit the right account.
          // Also drop the magnet themselves — magnets frequently reply to
          // their own comment threads and we don't want to "prospect" them.
          const magnetProfile = magnet.linkedin_url.replace(/\/+$/, '').toLowerCase();
          const filteredComments = [];
          for (const c of comments) {
            const commenterProfile = (c.profile_url || '').replace(/\/+$/, '').toLowerCase();
            if (commenterProfile && commenterProfile === magnetProfile) {
              continue; // skip self-replies by the magnet
            }
            c.source_magnet_id = magnet.id;
            filteredComments.push(c);
          }
          allCommenters.push(...filteredComments);
          postsVisited++;

          // Inter-post delay so we don't slam two posts back-to-back
          await humanize.dwell(15000, 30000);
        } catch (e) {
          log.error(`Failed to extract from post ${postUrl}: ${e.message}`);
        }
      }
    }

    // Filter the harvested commenters
    const filter = new CommenterFilter(log);
    const filterResults = filter.filter(allCommenters);
    filter.close();

    // CRITICAL ORDERING: persist the BDR handoff file and magnet rotation
    // state BEFORE the cooldown. The cooldown is cosmetic human-mimicry and
    // occasionally fails with ERR_CONNECTION_CLOSED or a dead CDP session;
    // when that happened we used to lose the entire run's output. Save the
    // product first, then do the cosmetic wind-down.
    const outputPath = await writeOutput({
      sessionId,
      magnetsUsed: magnets.map((m) => m.id),
      stats: {
        posts_visited: postsVisited,
        raw_commenters: allCommenters.length,
        passed_filter: filterResults.passed.length,
        rejected: filterResults.rejected,
      },
      prospects: filterResults.passed,
    });
    log.info(`Output written to ${outputPath}`);

    // Update magnet rotation (cooldowns + history)
    await recordMagnetUse(ROTATION_PATH, magnets, {
      commenters_extracted: allCommenters.length,
      commenters_passed_filter: filterResults.passed.length,
    });

    log.info(
      `Run complete. ${filterResults.passed.length}/${allCommenters.length} commenters passed filter`
    );

    // Cooldown routine: back to feed, idle, exit. Wrapped in try/catch so a
    // cosmetic cooldown failure never loses the already-written output.
    try {
      await humanize.cooldownSession(log);
    } catch (e) {
      log.warn(`Cooldown failed (non-fatal, output already saved): ${e.message}`);
    }

    // Post-run state summary so the operator can see budget + cooldowns at a
    // glance. Must come AFTER recordMagnetUse + recordPageLoad so the numbers
    // reflect this run's writes.
    await logStateSummary(log);
  } finally {
    await context.close().catch(() => {});
  }
}

main().catch((e) => {
  process.stderr.write(`FATAL: ${e?.stack || e}\n`);
  process.exit(1);
});
