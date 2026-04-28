// Human-mimicry layer. Three concerns:
//   1. Mouse movement (Bezier curves via ghost-cursor) instead of teleport
//   2. Variable wait times with jitter (no fixed delays)
//   3. Backscroll, idle drift, warmup/cooldown sequences
//
// ghost-cursor-playwright's actions.move() only accepts string selectors,
// but we work with Locators throughout the extractor — so moveAndClick()
// computes the bounding box manually and uses moveTo() + click().

import { createCursor } from 'ghost-cursor-playwright';

function jitter(base, range = 0.6) {
  // Returns base * (1 ± range/2). e.g. base=200, range=0.6 → 140..260
  return Math.floor(base * (1 - range / 2 + Math.random() * range));
}

function randInt(min, max) {
  return min + Math.floor(Math.random() * (max - min));
}

export class Humanizer {
  constructor(page) {
    this.page = page;
    this.cursor = null;
  }

  async init() {
    // ghost-cursor-playwright's `debug` flag (4th arg, default true) installs a
    // visual mouse pointer overlay via `page.on('load', () => page.evaluate(...))`.
    // The listener is unhandled-rejection-unsafe: during a navigation, the
    // evaluate call races the lifecycle and throws "Execution context was
    // destroyed", crashing the whole scrape. We don't need the overlay (real
    // Chrome cursor is visible in headed mode), so pass debug=false to skip
    // installing the helper entirely. The Cursor itself still works — only the
    // cosmetic pointer dot is disabled.
    this.cursor = await createCursor(this.page, 10, 120, false);
  }

  // Wait between min and max ms (uniform random)
  async dwell(minMs, maxMs) {
    const ms = randInt(minMs, maxMs);
    await this.page.waitForTimeout(ms);
  }

  // Hard-timeout wrapper around page.goto. Playwright's built-in `timeout`
  // fires correctly when the CDP session is alive, but rebrowser-playwright's
  // protocol patches can leave us with a half-dead session where every CDP
  // call hangs forever and the internal timeout never fires. We race the goto
  // against a real setTimeout so the scraper can never hang on a single nav.
  // The promise rejects with a tagged error that the caller can catch and log.
  async safeGoto(url, { timeoutMs = 35000, waitUntil = 'domcontentloaded' } = {}) {
    let timer;
    const hardTimeout = new Promise((_, reject) => {
      timer = setTimeout(() => {
        reject(new Error(`safeGoto: hard timeout after ${timeoutMs}ms navigating to ${url}`));
      }, timeoutMs);
    });
    try {
      return await Promise.race([
        this.page.goto(url, { waitUntil, timeout: timeoutMs }),
        hardTimeout,
      ]);
    } finally {
      clearTimeout(timer);
    }
  }

  // Move cursor to a Locator's center via Bezier path, then click. Falls back
  // to a plain locator.click() if the bounding box is unavailable.
  async moveAndClick(locator) {
    let box = null;
    try {
      box = await locator.boundingBox({ timeout: 5000 });
    } catch {
      box = null;
    }
    if (!box) {
      // Element not in view; let Playwright scroll to it and click directly.
      await locator.click({ timeout: 10000 });
      await this.dwell(400, 900);
      return;
    }

    // Aim at a slightly randomized point inside the box (Fitts-Law-ish)
    const padX = box.width * 0.25;
    const padY = box.height * 0.25;
    const targetX = box.x + padX + Math.random() * (box.width - padX * 2);
    const targetY = box.y + padY + Math.random() * (box.height - padY * 2);

    try {
      await this.cursor.actions.moveTo({
        destination: { x: targetX, y: targetY },
        waitBeforeMove: [randInt(150, 400), randInt(400, 900)],
      });
      await this.cursor.actions.click({
        waitBeforeClick: [randInt(100, 250), randInt(250, 500)],
        waitBetweenClick: [randInt(20, 50), randInt(50, 120)],
      });
    } catch {
      // Bezier movement failed (e.g. cursor lib edge case); fall back
      await this.page.mouse.move(targetX, targetY, { steps: 10 });
      await this.page.mouse.click(targetX, targetY);
    }
    await this.dwell(400, 900);
  }

  // Variable scroll. 15% chance to backscroll partway (looks like re-reading).
  async scroll(direction = 'down', steps = 3) {
    for (let i = 0; i < steps; i++) {
      const baseDelta = jitter(180, 0.8);
      const delta = direction === 'down' ? baseDelta : -baseDelta;
      await this.page.mouse.wheel(0, delta);
      await this.dwell(jitter(250), jitter(450));
      if (Math.random() < 0.15) {
        await this.page.mouse.wheel(0, -Math.floor(delta * 0.3));
        await this.dwell(200, 500);
      }
    }
  }

  // Idle drift: small random mouse movements as if reading. Uses moveTo so
  // each hop is a Bezier curve.
  async idleDrift(seconds = 3) {
    const hops = Math.max(1, Math.floor(seconds));
    for (let i = 0; i < hops; i++) {
      const x = 200 + Math.random() * 1000;
      const y = 200 + Math.random() * 600;
      try {
        await this.cursor.actions.moveTo({ destination: { x, y } });
      } catch {
        await this.page.mouse.move(x, y, { steps: 8 });
      }
      await this.dwell(700, 1300);
    }
  }

  // Warmup: feed scroll → notifications → mynetwork → ready for target.
  // This pattern looks like a normal user opening LinkedIn before doing anything.
  // Note: idleDrift() was removed from warmup/cooldown — ghost-cursor Bezier
  // movement on a busy LinkedIn page blows up runtime (thousands of CDP
  // mouse.move calls per second) and the scroll pattern alone is a sufficient
  // humanization signal. Dwells were also tightened from the original 2-min
  // steady-state target to ~60s first-run-friendly values.
  async warmupSession(log) {
    log.info('Warm-up: feed (~40s)');
    await this.page.goto('https://www.linkedin.com/feed/', { waitUntil: 'domcontentloaded' });
    await this.dwell(2000, 3000);
    await this.scroll('down', 8);
    await this.scroll('down', 5);
    await this.dwell(4000, 6000);

    log.info('Warm-up: notifications (~10s)');
    await this.page.goto('https://www.linkedin.com/notifications/', { waitUntil: 'domcontentloaded' });
    await this.dwell(8000, 12000);
    await this.scroll('down', 2);

    log.info('Warm-up: mynetwork (~10s)');
    await this.page.goto('https://www.linkedin.com/mynetwork/', { waitUntil: 'domcontentloaded' });
    await this.dwell(8000, 12000);
    await this.scroll('down', 2);
  }

  // Cooldown: back to feed, idle, then exit.
  async cooldownSession(log) {
    log.info('Cooldown: feed scroll (~20s)');
    await this.page.goto('https://www.linkedin.com/feed/', { waitUntil: 'domcontentloaded' });
    await this.dwell(2000, 4000);
    await this.scroll('down', 3);
    await this.dwell(10000, 18000);
  }
}
