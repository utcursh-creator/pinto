// Launches a real Google Chrome instance via rebrowser-playwright with a
// persistent context. We rely on rebrowser-playwright's CDP patches (the
// Runtime.enable leak fix is the #1 detection vector in 2026) plus a layered
// JS-level stealth init script. Real Chrome (channel: 'chrome') is REQUIRED —
// bundled Chromium has a different TLS fingerprint that LinkedIn detects.
//
// About the "[rebrowser-patches][frames._context] cannot get world" stderr
// line: this is a ONE-SHOT init race in the default 'addBinding' fix mode
// that fires once when the first navigation outpaces the runtime binding
// bootstrap. It is cosmetic — rebrowser-patches catches and retries via the
// success path, so downstream page operations are unaffected. We tried
// switching to 'alwaysIsolated' (via REBROWSER_PATCHES_RUNTIME_FIX_MODE) to
// suppress it but that mode fails to establish the persistent context on
// this Chrome build with --remote-debugging-pipe ("Target page, context or
// browser has been closed" immediately after launch). The cleaner fix is to
// live with the one-line log and treat it as harmless init noise.

import { chromium } from 'rebrowser-playwright';
import path from 'path';
import fs from 'fs/promises';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROFILE_DIR = path.join(__dirname, '..', '.browser-profile');
const PREFS_PATH = path.join(PROFILE_DIR, 'Default', 'Preferences');
const SESSIONS_DIR = path.join(PROFILE_DIR, 'Default', 'Sessions');

// When a Chrome profile is force-killed (orphaned child processes after a task
// stop, a crash, etc.), Chrome writes `exit_type: "Crashed"` into Preferences.
// On the next launch, Chrome tries to show a "Restore pages?" session-restore
// bubble. With `--remote-debugging-pipe` the bubble is NOT dismissible, so
// Playwright hangs for several minutes before the page body finally resolves
// as empty. Resetting `exit_type` to `Normal` + `exited_cleanly: true` before
// every launch sidesteps the bubble entirely. `--hide-crash-restore-bubble` is
// a second belt-and-braces guard against future Chrome builds that might still
// surface the bubble despite clean prefs.
async function ensureCleanExitState() {
  try {
    const raw = await fs.readFile(PREFS_PATH, 'utf8');
    const prefs = JSON.parse(raw);
    let dirty = false;
    if (prefs?.profile?.exit_type && prefs.profile.exit_type !== 'Normal') {
      prefs.profile.exit_type = 'Normal';
      dirty = true;
    }
    if (prefs?.profile && prefs.profile.exited_cleanly !== true) {
      prefs.profile.exited_cleanly = true;
      dirty = true;
    }
    if (dirty) {
      await fs.writeFile(PREFS_PATH, JSON.stringify(prefs));
    }
  } catch {
    // Profile doesn't exist yet (first run) or Preferences is malformed — skip
    // the reset and let Chrome regenerate. Don't throw; a first-time login flow
    // is still valid.
  }
}

// Despite `--restore-last-session=false`, Chrome still rehydrates tabs from
// the `Default/Sessions/` directory across runs — orphaned-process restarts
// and unclean shutdowns leave a growing pile of zombie tabs that all open on
// the next launch ("pages=10" instead of "pages=1"). Each stale tab eats CDP
// attention, slows the protocol session, and contributes to the "session
// closed" race we see during navigation. Wiping the Sessions directory before
// launch gives us a clean single-tab boot every time. The Login Data, Cookies,
// and other auth state live in OTHER files and survive this wipe untouched.
async function purgeSessionState() {
  try {
    await fs.rm(SESSIONS_DIR, { recursive: true, force: true });
  } catch {
    // First run or already absent — nothing to do
  }
}

export async function launchBrowser({ headless = false } = {}) {
  await ensureCleanExitState();
  await purgeSessionState();

  const context = await chromium.launchPersistentContext(PROFILE_DIR, {
    channel: 'chrome',
    headless,
    viewport: { width: 1440, height: 900 },
    locale: 'en-US',
    timezoneId: 'Asia/Kolkata',
    permissions: ['geolocation', 'notifications'],
    args: [
      '--disable-blink-features=AutomationControlled',
      '--disable-features=IsolateOrigins,site-per-process,AutomationControlled',
      '--no-first-run',
      '--no-default-browser-check',
      '--password-store=basic',
      '--disable-component-update',
      '--disable-default-apps',
      '--disable-sync',
      '--metrics-recording-only',
      '--no-pings',
      '--hide-crash-restore-bubble',
      '--restore-last-session=false',
    ],
  });

  // Defense-in-depth on top of rebrowser-playwright's CDP patches.
  await context.addInitScript(() => {
    // Hide webdriver flag
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });

    // Realistic plugins array (real Chrome ships these)
    Object.defineProperty(navigator, 'plugins', {
      get: () => [
        { name: 'PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'Chrome PDF Viewer', filename: 'internal-pdf-viewer' },
        { name: 'Chromium PDF Viewer', filename: 'internal-pdf-viewer' },
      ],
    });

    // Fix WebGL vendor/renderer to look like a real Intel GPU
    const getParameter = WebGLRenderingContext.prototype.getParameter;
    WebGLRenderingContext.prototype.getParameter = function (parameter) {
      if (parameter === 37445) return 'Intel Inc.';
      if (parameter === 37446) return 'Intel Iris OpenGL Engine';
      return getParameter.call(this, parameter);
    };

    // Notification permission consistency (matches Notification.permission)
    const originalQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = (parameters) =>
      parameters.name === 'notifications'
        ? Promise.resolve({ state: Notification.permission })
        : originalQuery(parameters);

    // Remove ChromeDriver runtime markers
    delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
    delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
    delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;
  });

  // Belt-and-suspenders: even with session purge, Chrome occasionally spawns
  // multiple pages on first launch (welcome tabs, restored URLs from a
  // half-flushed session file). Collapse to a single working page so the rest
  // of the scraper has predictable state and we don't lose CDP attention to
  // zombie tabs.
  await collapseToSinglePage(context);

  return context;
}

// Reduce the context's pages to exactly one. Prefer the first non-blank page
// (to preserve any restored auth state), but if all are blank we keep the
// first one. If there are zero pages we open a fresh one.
async function collapseToSinglePage(context) {
  const pages = context.pages();
  if (pages.length === 0) {
    await context.newPage();
    return;
  }
  if (pages.length === 1) return;

  // Keep the first page, close the rest
  const [keep, ...extras] = pages;
  for (const p of extras) {
    try {
      await p.close({ runBeforeUnload: false });
    } catch {
      // Page may already be closing — ignore
    }
  }
  // If the kept page is on a blank/internal URL, navigate it to about:blank so
  // the next caller starts from a known state instead of inheriting whatever
  // tab Chrome restored.
  try {
    const url = keep.url();
    if (url.startsWith('chrome://') || url === '') {
      await keep.goto('about:blank', { timeout: 5000 }).catch(() => {});
    }
  } catch {
    // Ignore — page state will be replaced by the first real navigation
  }
}

export const PROFILE_DIR_PATH = PROFILE_DIR;
