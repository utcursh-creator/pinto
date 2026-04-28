#!/usr/bin/env node
// Suppress ghost-cursor rand spam (same as index.js).
const __origConsoleLog = console.log.bind(console);
console.log = (...args) => {
  if (args.length === 1 && args[0] === 'rand') return;
  __origConsoleLog(...args);
};

// One-off diagnostic: open a magnet's activity feed, hydrate it, scroll,
// then dump a bunch of selector hit-counts plus a truncated HTML snapshot
// so we can eyeball what LinkedIn is actually rendering there. Does NOT
// touch the rate limiter or write to output — it's a pure inspection tool.
//
// Usage:
//   node src/debug-activity.js                          # defaults to ben-van-sprundel
//   node src/debug-activity.js https://www.linkedin.com/in/OTHER/

import { launchBrowser } from './browser.js';
import { isLoggedIn } from './auth.js';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEBUG_DIR = path.join(__dirname, '..', 'debug');

const DEFAULT_PROFILE = 'https://www.linkedin.com/in/benvansprundel/';

async function main() {
  const argProfile = process.argv[2] || DEFAULT_PROFILE;
  const profileUrl = argProfile.endsWith('/') ? argProfile : argProfile + '/';
  const activityUrl = `${profileUrl}recent-activity/all/`;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

  await fs.mkdir(DEBUG_DIR, { recursive: true });

  console.log(`[debug-activity] Launching browser`);
  const context = await launchBrowser({ headless: false });
  const page = context.pages()[0] || (await context.newPage());

  try {
    const status = await isLoggedIn(page);
    console.log(`[debug-activity] loggedIn=${status.loggedIn} restricted=${status.restricted}`);
    if (!status.loggedIn) {
      console.log('[debug-activity] Not logged in, aborting');
      return;
    }

    console.log(`[debug-activity] Navigating to ${activityUrl}`);
    await page.goto(activityUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    // Hydration wait + gentle scroll to kick React
    await page.waitForTimeout(6000);
    for (let i = 0; i < 6; i++) {
      await page.mouse.wheel(0, 800);
      await page.waitForTimeout(800);
    }
    await page.waitForTimeout(3000);

    // Candidate selectors to probe
    const candidates = [
      // Our current selectors
      "a[href*='/feed/update/urn:li:activity:']",
      "a[href*='linkedin.com/posts/']",
      // URN-based containers (resilient to anchor-vs-div shift)
      "div[data-urn^='urn:li:activity:']",
      "div[data-id^='urn:li:activity:']",
      "article[data-urn^='urn:li:activity:']",
      "*[data-urn^='urn:li:activity:']",
      "*[data-id^='urn:li:activity:']",
      // React/feed-shared class patterns
      "div.feed-shared-update-v2",
      "div[data-view-name='feed-full-update']",
      "div.occludable-update",
      "div.profile-creator-shared-feed-update__container",
      // Generic post surfaces
      "main a[href*='activity']",
      "main a[href*='/posts/']",
      "main a[href*='/feed/update/']",
      // Feed update list wrappers
      "ul.scaffold-finite-scroll__content",
      "div.scaffold-finite-scroll__content",
    ];

    const counts = {};
    for (const sel of candidates) {
      try {
        counts[sel] = await page.locator(sel).count();
      } catch (e) {
        counts[sel] = `ERROR: ${e.message}`;
      }
    }

    // Gather any data-urn attributes on the page (top 20)
    const urns = await page.evaluate(() => {
      const els = Array.from(document.querySelectorAll('[data-urn]'));
      return els.slice(0, 20).map((el) => ({
        urn: el.getAttribute('data-urn'),
        tag: el.tagName.toLowerCase(),
        cls: el.className?.toString().slice(0, 80) || null,
      }));
    });

    // Gather any data-id attributes (top 20)
    const dataIds = await page.evaluate(() => {
      const els = Array.from(document.querySelectorAll('[data-id]'));
      return els.slice(0, 20).map((el) => ({
        id: el.getAttribute('data-id'),
        tag: el.tagName.toLowerCase(),
      }));
    });

    // All href values in main that look post-ish
    const hrefs = await page.evaluate(() => {
      const els = Array.from(document.querySelectorAll("main a[href]"));
      return els
        .map((el) => el.getAttribute('href'))
        .filter(
          (h) =>
            h &&
            (h.includes('activity') || h.includes('/posts/') || h.includes('/feed/update/'))
        )
        .slice(0, 20);
    });

    const mainPresent = await page.locator("main[role='main']").count();
    const mainInnerHTMLLength = await page.locator("main[role='main']").evaluate((el) => el.innerHTML.length).catch(() => 0);

    const report = {
      url: page.url(),
      title: await page.title(),
      main_present: mainPresent,
      main_innerhtml_length: mainInnerHTMLLength,
      selector_counts: counts,
      sample_urns: urns,
      sample_data_ids: dataIds,
      sample_hrefs: hrefs,
      timestamp: new Date().toISOString(),
    };

    const reportPath = path.join(DEBUG_DIR, `activity-probe-${stamp}.json`);
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2));
    console.log(`[debug-activity] Report written to ${reportPath}`);

    // Also grab an HTML snapshot for offline eyeballing
    const html = await page.content();
    const htmlPath = path.join(DEBUG_DIR, `activity-${stamp}.html`);
    await fs.writeFile(htmlPath, html);
    console.log(`[debug-activity] HTML snapshot written to ${htmlPath} (${html.length} bytes)`);

    // Summary to stdout
    console.log('\n=== Selector counts ===');
    for (const [sel, c] of Object.entries(counts)) {
      console.log(`  ${c}\t${sel}`);
    }
    console.log('\n=== Sample data-urn (first 20) ===');
    for (const u of urns) {
      console.log(`  ${u.urn}  <${u.tag}>  ${u.cls}`);
    }
    console.log('\n=== Sample matching hrefs (first 20) ===');
    for (const h of hrefs) console.log(`  ${h}`);
  } finally {
    await page.waitForTimeout(2000);
    await context.close().catch(() => {});
  }
}

main().catch((e) => {
  process.stderr.write(`FATAL: ${e?.stack || e}\n`);
  process.exit(1);
});
