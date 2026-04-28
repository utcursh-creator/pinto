# Vibelife Scraper

LinkedIn comment mining for the Vibelife prospecting pipeline. Uses a dummy account + Playwright (rebrowser-patched) to mine magnet account comment sections, applies a 4-stage filter, and hands qualified commenters to the BDR Paperclip agent.

> **WARNING:** This script controls a real LinkedIn account. Read the safety rules before running. Hard rate limits and a circuit breaker exist for a reason — never bypass them.

## Architecture

```
Magnet account list → Playwright (real Chrome, persistent context)
  → warm-up routine → recent activity feed → 1-2 posts per magnet
  → expand comments → extract → 4-stage filter
  → output/raw-prospects.json → BDR (Paperclip)
```

## Setup

1. **Install:**
   ```
   cd Tools/paperclip/scraper
   pnpm install
   npx rebrowser-playwright install chrome
   ```

2. **First-time login (manual, REQUIRED):**
   ```
   pnpm run login
   ```
   Browser opens to LinkedIn login. Log in with the dummy account. Press ENTER in terminal when feed visible.

3. **Health check:**
   ```
   pnpm run health
   ```
   Should output `loggedIn=true, restricted=false`.

## Running

```
pnpm run scrape
```

Watch the headed browser. Do not interact with it.

## Exit Codes

| Code | Meaning | Action |
|---|---|---|
| 0 | Success | BDR handoff JSON written to `output/` |
| 1 | Crash | Check `logs/scrape-{date}.log` |
| 97 | Not logged in | Run `pnpm run login` |
| 98 | Rate limit reached | Wait until tomorrow |
| 99 | Restriction signal / circuit breaker | DO NOT RETRY. Wait 72h. |

## Recovering from Circuit Breaker

1. Check `state/circuit-breaker.json` for severity and reason
2. Hard signal → wait 72 hours, do nothing
3. Soft signal → wait 24 hours
4. After cooldown: delete `state/circuit-breaker.json`
5. Lower rate limits temporarily for the first run after cooldown

## Managing Magnet Accounts

Magnet accounts are the LinkedIn profiles whose comment sections we mine. They live in [config/magnet-accounts.json](config/magnet-accounts.json) split into `segment_1_agencies` (AI automation agencies) and `segment_2_creators` (AI content creators).

**Adding a magnet:**

1. Pick a practitioner whose audience overlaps Vibelife's ICP (not the practitioner themselves — the people who comment on their posts)
2. Append to the correct segment array in `config/magnet-accounts.json`:
   ```json
   {
     "id": "kebab-case-id",
     "name": "Display Name",
     "linkedin_url": "https://www.linkedin.com/in/slug/",
     "priority": "high",
     "expected_comment_quality": 0.6,
     "notes": "Why this audience fits the ICP"
   }
   ```
3. `priority` (`high`/`medium`/`low`) and `expected_comment_quality` (0.0-1.0) drive the weighted picker
4. No restart required — next scrape picks it up

**Removing a magnet:**

Delete the entry. If it was in `state/magnet-rotation.json` cooldown, you can also delete the cooldown entry for that id (optional).

**Cooldown:** Each magnet has a 3-day cooldown after being mined. All magnets in cooldown → scrape halts. Keep at least 4-5 per segment to ensure picker always has eligible targets.

## Updating Selectors When LinkedIn DOM Changes

Symptom: scrape produces 0 commenters extracted, or logs show "Post container not found".

1. Open browser DevTools on a real LinkedIn post
2. Find new selector for the broken field
3. Add to TOP of fallback chain in [config/selectors.json](config/selectors.json) (first-match-wins)
4. Re-run — no code changes, no restart
5. Commit with message like `fix(scraper): update comment.name selector for DOM change`

## Paperclip Agent Integration

This scraper is orchestrated by the **Scraper** Paperclip agent (`fa075941-d41b-4f11-9a86-c60ede3528a6`, reports to BDR). The agent is a thin wrapper around this script:

1. Scraper agent wakes (on-demand or via assignment)
2. Pre-flight: checks circuit breaker, rate counters, session health
3. Runs `pnpm run scrape`
4. Validates `output/raw-prospects.json`
5. Creates a `[SCRAPER INPUT]` subtask for BDR with the path + stats
6. BDR enriches via Apollo `people/match`, qualifies per segment, hands to SDR
7. SDR → Writer → Editor → ready-to-send outreach

See the Scraper agent's `AGENTS.md` for full heartbeat procedure and safety rules.

## Files

```
src/             — Modules (browser, auth, navigator, extractor, filter, detector, humanize, rate-limiter, storage, logger, index)
config/          — magnet-accounts.json, selectors.json
state/           — Persistent state (gitignored): circuit-breaker, rate-counters, magnet-rotation, scrape-history.db
output/          — raw-prospects.json (handoff to BDR, gitignored)
logs/            — Per-run structured logs (gitignored)
.browser-profile/ — Chrome persistent profile (gitignored, holds session cookies)
test/            — Unit tests for pure-logic modules
```

## Safety Rules

1. NEVER edit `src/rate-limiter.js` to raise limits
2. NEVER bypass the circuit breaker
3. NEVER run more than 1 cycle per day
4. NEVER use the real LinkedIn account with this script
5. ALWAYS run headed (`headless: false`) in production
6. ALWAYS watch first run visually
