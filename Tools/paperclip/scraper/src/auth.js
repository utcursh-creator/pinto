// Auth + session validation. We never automate the login form (the dummy
// account is logged in once manually and the persistent context keeps the
// session). isLoggedIn navigates to /feed and checks for any of several
// "logged-in" sentinels in the DOM; if redirected to login or any /checkpoint/
// URL, we either need re-auth or have hit a restriction.

const FEED_URL = 'https://www.linkedin.com/feed/';
const LOGIN_URL = 'https://www.linkedin.com/login';

const RESTRICTION_URL_FRAGMENTS = [
  '/uas/login',
  '/checkpoint/challenge',
  '/checkpoint/lg/login-submit',
  '/authwall',
];

// Multiple "you are logged in" sentinels — LinkedIn rotates DOM regularly so
// we don't trust any single one. The global nav header is the most stable.
const LOGGED_IN_SENTINELS = [
  'header.global-nav',
  'nav.global-nav',
  '#global-nav',
  'a[data-link-to="profile"]',
  'div.feed-identity-module',
  'div.scaffold-layout__main',
  'main.scaffold-finite-scroll',
  'main[role="main"]',
  'main',
];

async function detectLoggedInSentinel(page, timeoutMs = 3000) {
  for (const sel of LOGGED_IN_SENTINELS) {
    const visible = await page
      .locator(sel)
      .first()
      .isVisible({ timeout: timeoutMs })
      .catch(() => false);
    if (visible) return sel;
  }
  return null;
}

export async function isLoggedIn(page) {
  let response;
  try {
    response = await page.goto(FEED_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } catch (e) {
    return { loggedIn: false, restricted: false, error: e.message };
  }

  const finalUrl = page.url();

  // Hard fail: redirected to checkpoint or login
  for (const fragment of RESTRICTION_URL_FRAGMENTS) {
    if (finalUrl.includes(fragment)) {
      return {
        loggedIn: false,
        restricted: fragment.includes('checkpoint'),
        finalUrl,
      };
    }
  }

  // Confirm we're actually on /feed/ (not redirected somewhere else)
  if (!finalUrl.includes('linkedin.com/feed')) {
    return { loggedIn: false, restricted: false, finalUrl, reason: 'not on feed url' };
  }

  // DOM sentinel check (any of several fallbacks). LinkedIn is a React SPA,
  // so the sentinels don't exist at `domcontentloaded` — we have to give the
  // framework a beat to hydrate. The nav header is the most consistent
  // post-hydration anchor, so we wait on it specifically before starting the
  // fallback loop.
  await page
    .locator('header.global-nav, nav.global-nav, #global-nav')
    .first()
    .waitFor({ state: 'visible', timeout: 8000 })
    .catch(() => {});

  const matchedSentinel = await detectLoggedInSentinel(page, 5000);

  // If no sentinel matched, capture diagnostic info so the operator can tell
  // whether LinkedIn returned a real logged-in feed, a logged-out landing
  // page, or served a stripped/CAPTCHA page. Cheap (~300 chars), only on
  // failure.
  let bodyPreview = null;
  let bodyLength = 0;
  let title = null;
  if (matchedSentinel === null) {
    title = await page.title().catch(() => null);
    const raw = await page
      .locator('body')
      .textContent({ timeout: 2000 })
      .catch(() => null);
    bodyLength = (raw || '').length;
    bodyPreview = (raw || '').replace(/\s+/g, ' ').slice(0, 300);
  }

  return {
    loggedIn: matchedSentinel !== null,
    restricted: false,
    finalUrl,
    sentinel: matchedSentinel,
    httpStatus: response?.status() ?? null,
    bodyPreview,
    bodyLength,
    title,
  };
}

// Polls for login success by watching the page URL. Avoids stdin completely
// so this works whether the script is run from a terminal or spawned by an
// agent. The user just logs in to LinkedIn in the opened window; the script
// auto-detects success and exits.
export async function manualLogin(page, log, { maxWaitMs = 10 * 60 * 1000, pollIntervalMs = 2000 } = {}) {
  log.info('Opening LinkedIn login page. Please log in in the browser window.');
  log.info(`Waiting up to ${Math.floor(maxWaitMs / 60000)} minutes for login to complete...`);

  await page.goto(LOGIN_URL, { waitUntil: 'domcontentloaded' });

  const start = Date.now();
  let lastProgressLog = 0;
  let consecutiveFeedHits = 0;

  while (Date.now() - start < maxWaitMs) {
    await page.waitForTimeout(pollIntervalMs);
    const url = page.url();

    // Hard restriction during login = abort immediately
    for (const fragment of RESTRICTION_URL_FRAGMENTS) {
      if (fragment === '/uas/login') continue; // /uas/login is the login page itself
      if (url.includes(fragment)) {
        throw new Error(`Restriction encountered during login: ${url}`);
      }
    }

    // Successful login lands the user on /feed/ (or /feed)
    if (url.includes('linkedin.com/feed')) {
      consecutiveFeedHits++;

      // First try DOM sentinel
      const sentinel = await detectLoggedInSentinel(page, 1500);
      if (sentinel) {
        log.info(`Manual login succeeded. Final URL: ${url} (sentinel=${sentinel})`);
        log.info('Persistent context saved. Future runs will reuse this session.');
        return;
      }

      // Fallback: 3 consecutive polls on /feed/ without sentinel = treat as
      // success (DOM sentinels can lag or LinkedIn rotated them all again).
      // The URL is the strongest single signal.
      if (consecutiveFeedHits >= 3) {
        log.warn(
          `On /feed/ for ${consecutiveFeedHits} polls without DOM sentinel match — accepting URL as proof of login`
        );
        log.info(`Manual login succeeded (URL-only). Final URL: ${url}`);
        log.info('Persistent context saved. Future runs will reuse this session.');
        return;
      }
    } else {
      consecutiveFeedHits = 0;
    }

    // Log progress every 30s so the operator knows the script is alive
    if (Date.now() - lastProgressLog > 30000) {
      log.info(`Still waiting for login... current URL: ${url}`);
      lastProgressLog = Date.now();
    }
  }

  throw new Error(
    `Manual login timed out after ${Math.floor(maxWaitMs / 1000)}s. Last URL: ${page.url()}`
  );
}
