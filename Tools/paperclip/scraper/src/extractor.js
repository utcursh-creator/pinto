// LinkedIn comment extractor. Loads selectors from config (so we can hot-fix
// DOM changes without code edits) and tries each fallback in order. Critical
// behaviors:
//   - Dwell + scroll like a reader
//   - Click "load more comments" up to 3 times per post (not infinitely)
//   - Skip malformed comments (no name or no profile link)
//   - Normalize profile URLs to a canonical form for dedupe

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SELECTORS_PATH = path.join(__dirname, '..', 'config', 'selectors.json');

let _selectors = null;
async function loadSelectors() {
  if (_selectors) return _selectors;
  const text = await fs.readFile(SELECTORS_PATH, 'utf8');
  _selectors = JSON.parse(text);
  return _selectors;
}

// First-match-wins selector resolver. `scope` may be a Page or a Locator.
async function trySelectors(scope, selectorList) {
  for (const sel of selectorList) {
    const el = scope.locator(sel).first();
    try {
      if ((await el.count()) > 0) return el;
    } catch {
      // ignore and try next
    }
  }
  return null;
}

async function extractText(scope, selectorList) {
  const el = await trySelectors(scope, selectorList);
  if (!el) return null;
  try {
    const text = await el.textContent({ timeout: 2000 });
    return text ? text.trim() : null;
  } catch {
    return null;
  }
}

async function extractAttribute(scope, selectorList, attr) {
  const el = await trySelectors(scope, selectorList);
  if (!el) return null;
  try {
    return await el.getAttribute(attr, { timeout: 2000 });
  } catch {
    return null;
  }
}

function normalizeProfileUrl(url) {
  if (!url) return null;
  const match = url.match(/linkedin\.com\/in\/([^/?#]+)/);
  return match ? `https://www.linkedin.com/in/${match[1]}/` : null;
}

export async function extractCommentsFromPost(page, postUrl, humanize, log) {
  const SELECTORS = await loadSelectors();
  log.info(`Navigating to post: ${postUrl}`);
  // safeGoto adds a hard Promise.race timeout so a dead CDP session can't hang
  // the scraper indefinitely. See humanize.safeGoto for the rationale.
  await humanize.safeGoto(postUrl, { timeoutMs: 35000 });
  await humanize.dwell(8000, 15000); // look like reading
  await humanize.scroll('down', 3);

  // Find post container (validates we're actually on a post page)
  const post = await trySelectors(page, SELECTORS.post.container);
  if (!post) {
    log.warn('Post container not found - DOM may have changed or post is unavailable');
    return [];
  }

  // Click comment count to expand if collapsed
  const commentBtn = await trySelectors(page, SELECTORS.post.comment_count_button);
  if (commentBtn) {
    try {
      await humanize.moveAndClick(commentBtn);
      await humanize.dwell(2000, 4000);
    } catch (e) {
      log.warn(`Failed to click comment count: ${e.message}`);
    }
  }

  // "Load more comments" loop — bounded to 3 expansions per post.
  for (let i = 0; i < 3; i++) {
    const loadMore = await trySelectors(page, SELECTORS.load_more_comments);
    if (!loadMore) break;
    let visible = false;
    try {
      visible = await loadMore.isVisible({ timeout: 1000 });
    } catch {
      visible = false;
    }
    if (!visible) break;
    try {
      await humanize.moveAndClick(loadMore);
      await humanize.dwell(2500, 5000);
    } catch (e) {
      log.warn(`Failed to expand more comments at iteration ${i}: ${e.message}`);
      break;
    }
  }

  // Collect all comment article elements (using all fallback selectors at once)
  const containerSelector = SELECTORS.comment.container.join(', ');
  let commentEls = [];
  try {
    commentEls = await page.locator(containerSelector).all();
  } catch (e) {
    log.warn(`Failed to query comment containers: ${e.message}`);
  }
  log.info(`Found ${commentEls.length} comment elements on post`);

  const comments = [];
  for (const el of commentEls) {
    const name = await extractText(el, SELECTORS.comment.name);
    const profileLink = await extractAttribute(el, SELECTORS.comment.profile_link, 'href');
    const headline = await extractText(el, SELECTORS.comment.headline);
    const body = await extractText(el, SELECTORS.comment.body);
    const imageEl = await trySelectors(el, SELECTORS.comment.image);
    const hasImage = imageEl !== null;

    if (!name || !profileLink) continue; // Skip malformed

    comments.push({
      name,
      profile_url: normalizeProfileUrl(profileLink),
      headline: headline || null,
      comment_text: body || null,
      has_profile_image: hasImage,
      source_post_url: postUrl,
      scraped_at: new Date().toISOString(),
    });
  }

  return comments;
}

// Helper for navigator-mode: pull post URLs from a magnet's recent activity feed.
//
// As of 2026-04, LinkedIn no longer renders profile activity items as <a href>
// tags — each post is a React-mounted `div[data-urn^='urn:li:activity:']` and
// clicks are handled by JS. So the primary extraction path is:
//   1. Wait for URN containers to hydrate
//   2. Read data-urn attribute from each container
//   3. Construct the canonical URL ourselves: `/feed/update/${urn}/`
//
// We keep the old anchor-based path as a fallback in case another profile
// layout still uses anchors (defence in depth against silent layout drift).
export async function extractRecentPostUrls(page, max = 2) {
  const SELECTORS = await loadSelectors();
  const containerSelector = SELECTORS.activity_feed_post_container.join(', ');
  const linkSelector = SELECTORS.activity_feed_post_link.join(', ');

  try {
    // Wait for either URN containers or anchors to hydrate. Whichever hits
    // first wins. An empty feed is a valid (if suspicious) outcome.
    await page
      .locator(`${containerSelector}, ${linkSelector}`)
      .first()
      .waitFor({ state: 'attached', timeout: 15000 })
      .catch(() => {});

    // Primary path: pull URNs from container data-urn attributes
    const urns = await page.locator(containerSelector).evaluateAll((els) =>
      Array.from(
        new Set(
          els
            .map((el) => el.getAttribute('data-urn'))
            .filter((u) => u && u.startsWith('urn:li:activity:'))
        )
      )
    );

    if (urns.length > 0) {
      const urls = urns.map((urn) => `https://www.linkedin.com/feed/update/${urn}/`);
      return urls.slice(0, max);
    }

    // Fallback: old anchor-based extraction (older LinkedIn layouts)
    const anchorUrls = await page
      .locator(linkSelector)
      .evaluateAll((els) =>
        Array.from(new Set(els.map((el) => el.href))).filter(
          (u) => u && u.includes('linkedin.com')
        )
      );
    return anchorUrls.slice(0, max);
  } catch {
    return [];
  }
}

// On zero-result post extraction, grab a compact page snapshot so the operator
// can tell whether LinkedIn served a logged-in activity page, a login wall, a
// "this profile is unavailable" shell, or an empty feed. Cheap and only fires
// on the failure path.
export async function captureActivityPageSnapshot(page) {
  const url = page.url();
  const title = await page.title().catch(() => null);
  const bodyRaw = await page
    .locator('body')
    .textContent({ timeout: 3000 })
    .catch(() => null);
  const bodyText = (bodyRaw || '').replace(/\s+/g, ' ').slice(0, 400);
  const bodyLength = (bodyRaw || '').length;

  // Count how many things that LOOK like activity links exist, to distinguish
  // "page is completely empty" from "our selectors are wrong".
  const looseLinkCount = await page
    .locator("a[href*='activity'], a[href*='/posts/'], a[href*='/feed/update/']")
    .count()
    .catch(() => 0);

  return { url, title, bodyLength, bodyPreview: bodyText, looseLinkCount };
}

export { normalizeProfileUrl };
