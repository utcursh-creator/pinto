# Personal Assistant OS — Auto Memory

## User: Anand Utkarsh
- Communication: context-dependent (concise for direct, detailed with reasoning when needed)
- Full positioning doc at `.claude/context/memory/CLAUDE.md`
- Memory system files at `.claude/context/memory/` (user_preferences, user_projects, work_status, learnings, **ott-strategy** [current primary])
- Detailed ICP, offer, micro-offer, perception, and thinking patterns in `user_preferences.md`

## CURRENT PRIMARY (2026-06-15): OTT video-editing pivot
Utkarsh is pivoting from AI-automation services to a PRODUCT in the video-editing niche: **OTT (One Take Tall)**, a calibrated SOP-compliance video-editing service for high-volume creator/UGC/product reels (~1-week calibration per client, then executes at volume with QC; runs for PulpKey). Product built; now building sales + marketing pipeline. Core problem: WEAK POSITIONING (perceived as employee not partner -> prospects demand free tests). Framework = 3 packages: ICP, OFFER, POSITIONING.
- **Full OTT brain: `.claude/context/memory/ott-strategy.md`** (read this for OTT work).
- **Assets: `Projects/ott-outbound/`** (campaign-brief.md = 5-account cold email; lead-list.md = 23 qualified leads, 4 Tier-1). System code at `/Users/utkarsh/ott`.

## Key People
- **Yosef** — Primary client (automation-services era). Utkarsh builds automations for him and his clients.
- **Sanchit** — brings word-of-mouth OTT prospects (the ones who demanded a free test = the positioning-problem trigger).
- **PulpKey** — OTT proof/reference client (product-reel editing runs for them in production).
- **Ben Van Sprundel** — Runs BenAI (benai.co). AI Accelerator community. Audience = Utkarsh's ICP.

## Active Projects
1. **OTT (One Take Tall) — PRIMARY, the pivot.** Video-editing product/service. GTM build: ICP/Offer/Positioning + sales + marketing pipeline. See `ott-strategy.md` + `Projects/ott-outbound/`.
2. Content Engine (BUILT this session) — Twitter-first, contrarian/frontier/security AI + primary research papers translated. Skill `content-engine` + `Projects/content-engine/` (spec, stage-playbook, voice-samples, proof-bank, copywriting-framework, braindump). Kanban board pending Obsidian verify.
--- prior-era (automation services), lower priority now ---
3. Yosef Client Work (revenue, delivery)
4. Internal Tools (own process automation)
5. Vibelife Website — repositioning: "fulfillment partner for AI automation businesses"
6. n8n Workflow Reviewer (built, needs deploy)
7. Paperclip Agent Orchestration — `Tools/paperclip/`, server on port 3100
(SCRAPPED: outbound prospect-scraper / job-board lead-gen — proven wrong channel, deleted, in git history.)

## Vibelife Website Status (2026-04-02)
- Approved hero: "We cleared 5 projects for one business in 21 days and they never touched fulfillment again"
- Subtext: "If you're stuck building everything yourself we should probably talk"
- Approved structure: Hero → Proof Bar → Problem → 3-Week Sandbox → Before/After → Trust → CTA
- Pending: Full implementation, cursor fix, Brand Bible update
- Session log: `.claude/context/session-logs/2026-04-02-2200-vibelife-redesign-gtm-pivot.md`

## Micro-Offer (Updated 2026-04-02)
3-week sandbox: audit project backlog → pick 2-5 most urgent builds → deliver in your tools → document everything. No pricing on landing page — discovery call handles that.

## ICP Geography & Segments
- US, UK, Australia, Canada + **EU (especially Germany)** — discipline + logic fit
- Segment A: AI automation agencies (1-5 people, $10-20K MRR)
- Segment B: AI content creator businesses (have distribution, need fulfillment) — Ben, Yosef
- Segment C: Business owners with domain expertise (secondary)

## Utkarsh's Full Skill Stack (NOT sold separately — context for partnerships)
- Brand visibility & conversion (good taste, makes visitors buy)
- Sales support (helps partners close)
- Business process design (maps ops, finds bottlenecks)
- Fulfillment building (core offer)

## Critical Content Rules (Do NOT Forget)
- Worldview = LENS, not SUBJECT. Content about audience's problems.
- Never reporter/news channel. Practitioner.
- DON'T be deterministic — understand his latent space, don't template from notes.
- DON'T repeat same topical territory (deployment gap covered 3x already).
- DON'T follow writing patterns literally — understand the THINKING MECHANISM.
- Go to primary sources first (a16z articles, not summaries).
- Dumb everything down — girlfriend's uncle level.
- Each post structurally different from the last.
- Hook must relate to the problem being discussed.

## Copywriting Rules (Learned 2026-04-02)
- Proof-first headlines > identity statements for this audience
- Specificity creates believability (Hopkins): "5 projects, 21 days" > "we handle fulfillment"
- Enter the conversation in the buyer's head (Schwartz), don't create desire
- Headline + subtext must flow as ONE thought — no jarring perspective shifts
- No pricing or internal GTM terminology on landing page
- Don't assume buyer's strength is sales — could be strategy, experimentation, etc.

## Paperclip Setup (2026-04-04)
- Server: http://127.0.0.1:3100 (pnpm dev from Tools/paperclip/)
- Data: `C:\Users\Utkarsh\.paperclip\instances\default\`
- Founders: Dotta (hedge fund), Devin Foley (Slack/Figma), Scott Tong (Pinterest)
- 46.6K GitHub stars, MIT license, v0.3.x, zero revenue
- Key concept: "Board of Directors" (you) → CEO agent → specialist agents
- Heartbeat system: agents wake on schedule, execute 9-step protocol, sleep
- Adapters: claude_local, codex_local, cursor, openclaw_gateway, http, process
- Budget: per-agent monthly limits, hard stop at 100%
- Research: `Research/paperclip-ai-platform-research.md`, `Reference/paperclip-ai-research.md`
- Skill: `paperclip` skill registered in `.claude/skills/` for API interaction
- Security note: third-party skills have full filesystem access — no sandbox yet

## System Notes
- TaskNotes API on port 8080 — requires Obsidian open
- Paperclip server on port 3100 — `pnpm dev` from `Tools/paperclip/`
- Vibelife dev server: port 7722, ngrok for preview
- Weekly review template enhanced with goal alignment check and burnout check
- Setup completed 2026-02-26
- Always check memory files before responding (per CLAUDE.md rules)
- Always update memory after significant interactions
- PDF reading on Windows: use pypdf (pdftoppm not available)
- GSAP ScrollTrigger + opacity bug: use FadeInView instead of gsap.from for scroll animations
- Brand system: NEVER use multicolor gradient text — solid text-gold or gold highlight bg only

## Vibelife LinkedIn Scraper (Tools/paperclip/scraper)
- 23-task plan at `C:\Users\Utkarsh\.claude\plans\twinkling-sniffing-leaf.md`, on Task 17
- rebrowser-playwright 1.52.0 + ghost-cursor-playwright 1.2.0 + real Chrome (`channel:'chrome'`) + persistent context at `.browser-profile/`
- LinkedIn 2026-04 DOM changes:
  - Activity feed: posts are `div[data-urn^='urn:li:activity:']` NOT `<a href>` — extract URN, build URL as `/feed/update/${urn}/`
  - Comments: new class is `comments-comment-meta__*` not `comments-post-meta__*`. Name=`.comments-comment-meta__description-title`, profile_link=`a.comments-comment-meta__image-link`, headline=`.comments-comment-meta__description-subtitle`
- Critical fixes for stability:
  - Always reset `Default/Preferences` `exit_type:"Normal"` before launch (crash recovery bubble blocks `--remote-debugging-pipe`)
  - Always purge `Default/Sessions/` before launch (orphaned tabs from prior runs accumulate, slow CDP)
  - Always pass `createCursor(page,10,120,false)` — `debug=true` installs racy mouse-helper
  - Always wrap `page.goto` in `Promise.race` hard timeout — Playwright's `timeout` doesn't fire when CDP session is half-dead
  - Add `process.on('unhandledRejection')` filter for benign nav races: 'Execution context was destroyed', 'Target closed'
  - Monkey-patch `console.log` to filter literal 'rand' string (ghost-cursor-playwright cursor.js:199 spam)
- Diagnostic scripts: `src/debug-activity.js` (probes activity feed selectors), `src/debug-comments.js` (probes comment selectors). Don't touch rate limiter.
