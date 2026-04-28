#!/usr/bin/env node
// Suppress ghost-cursor rand spam (same as index.js)
const __origConsoleLog = console.log.bind(console);
console.log = (...args) => {
  if (args.length === 1 && args[0] === 'rand') return;
  __origConsoleLog(...args);
};

// One-off diagnostic: open a single post URL, hydrate it, scroll to load
// comments, then dump selector hit-counts AND a sample of the FIRST comment
// element's outerHTML so we can see exactly which class names LinkedIn is
// using right now. Pure inspection — does NOT touch the rate limiter.
//
// Usage:
//   node src/debug-comments.js                    # uses a known Ben post URL
//   node src/debug-comments.js https://www.linkedin.com/feed/update/urn:li:activity:.../

import { launchBrowser } from './browser.js';
import { isLoggedIn } from './auth.js';
import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEBUG_DIR = path.join(__dirname, '..', 'debug');

const DEFAULT_POST = 'https://www.linkedin.com/feed/update/urn:li:activity:7443301800524341248/';

async function main() {
  const postUrl = process.argv[2] || DEFAULT_POST;
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

  await fs.mkdir(DEBUG_DIR, { recursive: true });

  console.log(`[debug-comments] Launching browser`);
  const context = await launchBrowser({ headless: false });
  const page = context.pages()[0] || (await context.newPage());

  try {
    const status = await isLoggedIn(page);
    console.log(`[debug-comments] loggedIn=${status.loggedIn}`);
    if (!status.loggedIn) {
      console.log('[debug-comments] Not logged in, aborting');
      return;
    }

    console.log(`[debug-comments] Navigating to ${postUrl}`);
    await page.goto(postUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(8000);

    // Try to click the comment count button to expand the comments section
    const commentBtnSelectors = [
      "button.social-details-social-counts__comments",
      "button[aria-label*='comment' i]",
      ".social-details-social-counts__comments button",
    ];
    for (const sel of commentBtnSelectors) {
      const btn = page.locator(sel).first();
      if ((await btn.count()) > 0) {
        try {
          await btn.click({ timeout: 3000 });
          console.log(`[debug-comments] Clicked comment button: ${sel}`);
          break;
        } catch (e) {
          console.log(`[debug-comments] Failed to click ${sel}: ${e.message}`);
        }
      }
    }
    await page.waitForTimeout(4000);

    // Scroll to load comments
    for (let i = 0; i < 5; i++) {
      await page.mouse.wheel(0, 800);
      await page.waitForTimeout(700);
    }
    await page.waitForTimeout(3000);

    // Candidate selectors to probe
    const containerSelectors = [
      "article[data-id*='urn:li:comment']",
      "article.comments-comment-entity",
      "article.comments-comment-item",
      "div.comments-comment-entity",
      "div[data-id*='urn:li:comment']",
      ".comments-comment-list article",
      ".comments-comments-list article",
    ];
    const nameSelectors = [
      ".comments-post-meta__name-text span[aria-hidden='true']",
      ".comments-post-meta__name span[aria-hidden='true']",
      ".comments-post-meta__name-link span[aria-hidden='true']",
      "a.comments-post-meta__profile-link span[aria-hidden='true']",
      ".comments-comment-meta__name span[aria-hidden='true']",
      ".comments-comment-meta__name-text span",
      ".comments-comment-meta__description-title",
      ".comments-comment-meta a span[aria-hidden='true']",
      "[data-test-id='comment-author-name']",
    ];
    const profileLinkSelectors = [
      "a.comments-post-meta__profile-link",
      ".comments-post-meta a[href*='/in/']",
      ".comments-post-meta__name a[href*='/in/']",
      ".comments-comment-meta a[href*='/in/']",
      "a.comments-comment-meta__image-link",
      "a[data-test-id='comment-author-link']",
    ];
    const headlineSelectors = [
      ".comments-post-meta__headline",
      ".comments-post-meta__description",
      ".comments-post-meta__subtitle",
      ".comments-comment-meta__description",
    ];
    const bodySelectors = [
      ".comments-comment-item__main-content",
      ".comments-comment-entity__main-content",
      ".comments-comment-item-content-body",
      ".comments-comment-content",
      ".comments-comment-item__content",
    ];

    const counts = {};
    const all = [
      ...containerSelectors,
      ...nameSelectors,
      ...profileLinkSelectors,
      ...headlineSelectors,
      ...bodySelectors,
    ];
    for (const sel of all) {
      try {
        counts[sel] = await page.locator(sel).count();
      } catch (e) {
        counts[sel] = `ERROR: ${e.message}`;
      }
    }

    // Dump first comment container's outerHTML so we can see real class names
    let firstCommentHtml = null;
    for (const sel of containerSelectors) {
      try {
        const c = await page.locator(sel).count();
        if (c > 0) {
          firstCommentHtml = await page
            .locator(sel)
            .first()
            .evaluate((el) => el.outerHTML.slice(0, 6000));
          console.log(`[debug-comments] Captured first comment HTML via: ${sel}`);
          break;
        }
      } catch {}
    }

    // Also: list ALL article elements with data-id attributes
    const articles = await page.evaluate(() => {
      const els = Array.from(document.querySelectorAll('article'));
      return els.slice(0, 5).map((el) => ({
        dataId: el.getAttribute('data-id'),
        cls: el.className?.toString().slice(0, 200),
        innerLen: el.innerHTML.length,
      }));
    });

    const report = {
      url: page.url(),
      title: await page.title(),
      selector_counts: counts,
      sample_articles: articles,
      first_comment_html_preview: firstCommentHtml,
      timestamp: new Date().toISOString(),
    };

    const reportPath = path.join(DEBUG_DIR, `comments-probe-${stamp}.json`);
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2));
    console.log(`[debug-comments] Report written to ${reportPath}`);

    // Print summary to stdout
    console.log('\n=== Selector counts ===');
    for (const [sel, c] of Object.entries(counts)) {
      console.log(`  ${c}\t${sel}`);
    }
    console.log('\n=== Sample <article> elements ===');
    for (const a of articles) {
      console.log(`  data-id=${a.dataId}  cls=${a.cls}  innerLen=${a.innerLen}`);
    }
    if (firstCommentHtml) {
      console.log('\n=== First comment outerHTML preview (6000 char) ===');
      console.log(firstCommentHtml);
    } else {
      console.log('\n=== NO COMMENT CONTAINER FOUND ===');
    }
  } finally {
    await page.waitForTimeout(2000);
    await context.close().catch(() => {});
  }
}

main().catch((e) => {
  process.stderr.write(`FATAL: ${e?.stack || e}\n`);
  process.exit(1);
});
