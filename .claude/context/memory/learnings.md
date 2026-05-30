---
type: memory
category: learnings
last_updated: 2026-05-28
---

# Learnings

## User's GTM Avoidance Pattern (2026-05-28)
Utkarsh has technical operator's classic blocker: defaults to build work whenever GTM/sales/positioning gets uncomfortable. Evidence: 4+ sessions on Offer/ICP/GTM brainstorm, each one pivoted to a technical project (Aramas scraper, ScreenStudio, paperclip, n8n-reviewer) before reaching offer language. The "I don't have time" framing is a symptom, not the cause — the pattern is comfort-seeking, not scheduling.
Implication for future sessions: don't accept "I'll make time next week" as a plan. Push to structural change: (a) outsource the GTM work (positioning consultant, sales partner), (b) accept that GTM-self-doing isn't going to happen and route around it (multiply Yosef-style technical partnerships), or (c) force external commitments that can't be deflected (booked calls). The wrong move is to keep restarting the brainstorm — pattern wins unless structure changes.

**In-session scope-creep variant (observed 2026-05-28)**: After committing to Path 1 (multiply Yosefs via tech-leveraged scraper), user expanded same session to include faceless YouTube channel on contrarian AI + ComfyUI storyboard pipeline + automated posting infra. Naming it as a "different workstream" doesn't change the bandwidth math: parallel workstreams = neither ships. Action when this happens: name the pattern out loud, validate the new idea has merit, force capture-and-park into /Inbox or /Thinking, keep sprint scope hard-locked.

**STRENGTHENED to a core signal (2026-05-28)**: In ONE session, user gravitated to building a content/distribution engine THREE times: (1) prospect-scraper, (2) faceless YouTube channel [parked], (3) Twitter content engine sourcing research→AI→business-nuggets. Each pivot moved away from directly contacting prospects and toward building a system. This is not random scope-creep, it's a consistent preference: user is drawn to building distribution/content infrastructure, and resistant to direct outreach. Likely the real strategy is content-led inbound, NOT direct outreach. But content-led is a 3-6 month audience play and does not satisfy a "2 partners in 30 days" goal. Future sessions: when user proposes a content engine, force the explicit goal-timeline reconciliation (fast revenue vs long-game distribution) before speccing. Don't let both run in parallel.

**Teaching loop working (2026-05-28)**: Later same session, user began drifting to "newsletter" then caught it himself mid-sentence ("Again, this is what I swayed to"). The named pattern is now self-visible to the user in real time. Keep naming drifts plainly and without judgment — it's transferring. When user catches their own sway, affirm it matter-of-factly (not cheerleader-y) and move on. Resolution for both-pipelines tension: build sequentially (shared core → outbound → inbound), never parallel; the bandwidth cost is in BUILD not RUN.

## Writer-agent target = information architecture, NOT voice (2026-05-29)
Utkarsh's content writer-agent should produce a DENSE first-draft optimized for information density + architecture (validated facts, framing, interest build-up, reveal sequence), NOT voice/beautification. He does the final voice polish himself. This dissolves the long-standing tension with his writing-style-analysis.md rule ("don't templatize my voice, you're a probabilistic system"): the machine handles the templatable layer (structure/info), the human handles the un-templatable layer (voice). When building any drafting tool for him, aim the machine at structure + density, leave voice to him, and treat the agent's output as a scaffold-to-react-to, not a finished piece. Voice samples (2 real posts) live in Projects/content-engine/voice-samples.md; thinking process in writing-style-analysis.md.

## Scraper build insights (2026-05-29)
- **WeWorkRemotely content-negotiates on Accept header**: default request (no Accept) returns an RSS/XML feed; `Accept: text/html` returns server-rendered HTML (~106 jobs, ~225KB). A generic get_text without the header = silent 0-jobs bug. WWR selectors: `li.new-listing-container` (entry), `span.new-listing__header__title__text` (title), `p.new-listing__company-name` (company), `a.listing-link--unlocked` (job link, relative href). Sponsored `li.listing-ad` entries lack a title so skip naturally.
- **Verify SOURCE ICP-yield, not just scraper correctness**: WWR's programming category + Utkarsh's narrow ICP keywords yielded 0 (broad "engineer" = 32). General job boards list companies hiring devs, not necessarily AGENCIES hiring automation partners (the actual ICP). Technical green tests do not mean a source surfaces fit prospects. The higher-yield sources for "agencies with delivery overflow" are likely Indeed with agency-targeted queries + the probing/qualification layers, not more general dev boards. Reconsider source priority accordingly.

## Git/SSH on this Mac (2026-05-28)
Port 22 is BLOCKED on the user's network (SSH-over-22 times out, HTTPS-443 works). GitHub SSH must go over port 443: `~/.ssh/config` has `Host github.com / Hostname ssh.github.com / Port 443 / User git`. Auth key = ed25519 at `~/.ssh/id_ed25519`. Remote = `git@github.com:utcursh-creator/pinto`. HTTPS password auth is dead (GitHub disabled it). git author identity is still auto-derived (utkarsh@utkarshs-MacBook-Pro-2.local) — user hasn't set global user.name/user.email. If pushes fail with timeout, it's the port-22 thing; the 443 config fixes it.

## Apify Actors for Scraping (researched 2026-05-28)
For job-board scraping, Apify pre-built actors offload anti-bot + maintenance. Free plan = ~$5/mo platform credits; pay-per-result charged against it (low volume = effectively free).
- **Indeed (incl. indeed.de)**: `borderline/indeed-scraper` is the pick ($5/1k, no login, DE support, 4.8/5, returns company website/industry/size). `misceres` is Apify-maintained but 3.3/5 + no documented non-US domains.
- **LinkedIn**: no-cookie actors (`get-leads/linkedin-scraper`, `harvestapi`) DO work in 2025-2026 via public endpoints, no account/ban risk, free-viable ($1-3/1k), BUT flaky (~3.3/5) and public-data-only. Cookie-based actors (`curious_coder`, 4.9/5) are rich+reliable but need YOUR session cookie (ban risk) + $30/mo rental. Rule: use no-cookie as a flaky bonus, never a hard dependency; validate each run.
- Apify actors typically DON'T return contact emails (still need separate enrichment), but DO return company website → can skip the company-resolution step.
- Reusable distinction: LinkedIn-as-data-source (scraping public data, fine) vs LinkedIn-as-channel (posting/outreach, which this user rejects). Different things.

## Positioning vs Channel Tension (2026-05-28)
User's positioning is high-tier (Forward Deployed AI Partner, peer not vendor). Templated cold-outreach in response to a job post is STRUCTURALLY vendor-tier no matter how the words are written. The medium codes the message before the words do. When proposing outreach for high-positioning operators, do not auto-default to job-post-response templates. Either: (a) accept the positioning compromise explicitly, (b) change the channel to peer-to-peer (slower), or (c) decouple the prospecting signal from the outreach narrative (use job post as intel only, email never references it). Surface this trade-off, don't paper over it.

## Tokio Reactor Requirement Is Broader Than Just spawn (2026-04-18)
Not only `tokio::spawn` requires a runtime — **any tokio I/O type conversion** that registers with the reactor also panics from non-runtime threads. Specifically:
- `tokio::net::TcpListener::from_std(std_listener)` — registers the socket with the I/O driver
- `tokio::net::TcpStream::from_std(std_stream)` — same
- `tokio::fs::File::from_std(std_file)` — same
- `tokio::signal::unix::signal(...)` — same

Symptom is identical: `there is no reactor running, must be called from the context of a Tokio 1.x runtime`. When debugging, check every tokio API call in the panic's file, not just `spawn`. Fix: move the conversion INSIDE an async task (via `tauri::async_runtime::spawn`) where runtime context is guaranteed.

## Tauri v2 Sync Commands Can't Call tokio::spawn (2026-04-18)
Tauri v2 dispatches synchronous `#[tauri::command]` functions on a blocking thread pool WITHOUT binding the tokio runtime handle to that thread. Calling `tokio::spawn(...)` from inside a sync command panics with: `there is no reactor running, must be called from the context of a Tokio 1.x runtime`. Two fixes:
- **Preferred**: use `tauri::async_runtime::spawn` instead — Tauri's wrapper uses its managed runtime and works from any thread context. Returns `tauri::async_runtime::JoinHandle<T>` which has `.abort()` and can be awaited like tokio's.
- **Alternative**: make the command `async fn` — then Tauri runs it on the async runtime and `tokio::spawn` works inside the call chain.
The error is silent in release builds (GUI subsystem = no stderr), so this class of bug hides until you have file-based logging.

## Tauri v2 Windows GUI Subsystem Has No Console (2026-04-18)
Release builds for Tauri v2 on Windows link with the GUI subsystem (`windows_subsystem = "windows"`), which means stdout/stderr are NOT attached to a parent terminal. `eprintln!` and `println!` output is discarded. When debugging a GUI app crash:
1. Don't rely on terminal output — write to a log file at `%LOCALAPPDATA%\<AppName>\debug.log` instead
2. Install `std::panic::set_hook` early in `run()` — writes panic payload + `std::backtrace::Backtrace::capture()` to the file
3. Wrap background threads in `std::panic::catch_unwind` so panics don't silently abort threads
4. For async tasks, use `futures_util::FutureExt::catch_unwind(AssertUnwindSafe(future))`
5. Use a `dlog!` macro so callers don't have to manually pass a file handle

Alternative: call `AllocConsole()` from Win32 to attach a console at runtime — more invasive.


## Tauri v2 Multi-Word Command Args (2026-04-17)
Tauri v2 auto-converts Rust `snake_case` command arg names to `camelCase` at the IPC boundary by default. A command `fn foo(mic_id: String)` expects JS to send `{ micId: ... }`, NOT `{ mic_id: ... }`. Single-word args (`target`, `state`) are unaffected since conversion is a no-op. Symptom: `invalid args 'micId' for command 'foo': missing required key micId`. Fix: `#[tauri::command(rename_all = "snake_case")]` on the command. Check every command with multi-word args (mic_id, frame_index, project_path, file_path, etc.) when adding new IPC.


## Tauri v2 Title Bar Buttons Not Working (2026-04-16, TRIPLE-CORRECTED)
**Symptom**: min/max/close buttons render but do nothing when clicked.
**Wrong diagnoses (wasted 3 attempts)**: assumed drag-region interception — tried splitting `data-tauri-drag-region`, then adding `-webkit-app-region: no-drag`. Neither was the issue.
**Actual root cause**: Tauri v2 permissions system. `capabilities/default.json` had only `core:default` which does NOT include window operation permissions. `getCurrentWindow().minimize()` IPC call was silently rejected (no `.catch()` on the returned promise → swallowed error). Fix: add explicit permissions `core:window:allow-minimize`, `allow-toggle-maximize`, `allow-close`, `allow-start-dragging`, `allow-set-focus`, `allow-show`.
**Lesson**: When Tauri IPC calls fail silently, check capabilities/permissions FIRST before debugging UI/DOM issues. Tauri v2's permission model is strict — every webview → Rust IPC call needs explicit permission in capabilities JSON. `core:default` is minimal and does NOT include window operations.

## User Preferences Noted (2026-04-15)
Prefers subagents use `opus` (4.6 with extended thinking) for non-trivial tasks — use sonnet/haiku only for purely mechanical work. Surface this when choosing models.

## Subagent-Driven Development Lessons (2026-04-15)
- Writing config that calls into itself recursively is a class of bug that mechanical review passes miss. `beforeBuildCommand: "pnpm build"` + `"build": "tauri build"` → infinite loop. `check:all` passed green because it doesn't run `tauri build`. Always trace what every npm script ACTUALLY INVOKES before shipping.
- Hand-rolled TypeScript ambient decls (.d.ts shims) will drift from the real library API. Include the full option surface or don't bother — a subtly wrong decl is worse than no decl (it lies to callers).
- Generic type boundaries like `invoke<K extends keyof EmptyMap>()` collapse to `never` when the map is empty, making the function uncallable-but-looks-typed. For a boundary that starts empty, either add a placeholder sentinel or don't ship the generics until the first real entry.
- Tauri's `capabilities/default.json` `:default` permissions are broad. Scope per-feature or the installer ships with shell.open + fs.read across a wide allowlist — security debt.
- Cargo `"2.0"` is caret-semver (`>=2.0, <3.0`). For pinning intent use `"=2.0.x"` or tilde `"~2.0"`. Otherwise commit Cargo.lock (for binary crates you should anyway).
- Vitest tests that only assert `getByText(...)` exists are cosmetic. If the handler surface (button clicks, keyboard shortcuts, router transitions) isn't exercised, check:all is green-but-meaningless.
- When a config change (like aliasing `build` to `tauri build`) crosses multiple files, ALWAYS trace the call graph both directions, not just forward.

## Screen Studio Clone — Core Architectural Insights (2026-04-15)
- For SS-style apps: the raw recording is NEVER baked. Compositor re-renders every frame from a JSON project config (non-destructive edits, preview = exporter on live frame).
- Auto-zoom is NOT AI. Deterministic pipeline: click-event clustering (bounded by zoomed-viewport size) → spring-smoothed focal point → edge-snap remap. Cap.so: `crates/rendering/src/zoom_focus_interpolation.rs`.
- Cursor smoothing = analytic spring-mass-damper per axis (frame-rate independent). NOT moving avg, NOT Kalman, NOT Catmull-Rom. Cap.so: `spring_mass_damper.rs`.
- WebView2 does not expose `ImportExternalTexture` for D3D11 shared handles — preview transport must be localhost WebSocket with raw RGBA/NV12 binary frames. Tauri IPC is too slow for per-frame payload.
- Win11 glass: `window-vibrancy` crate → `apply_mica` (main window) + `apply_acrylic` (popovers). Win10 fallback via `SetWindowCompositionAttribute`.
- Best open-source reference for any SS-style project: CapSoftware/Cap (Tauri v2 + Rust + SolidJS + wgpu + ffmpeg-next + windows-capture + cpal + nokhwa).

## Writer Agent Voice Debt (2026-04-15)
- Reading a voice library in a prompt is not the same as embodying it. The Writer agent's AGENTS.md points to voice-library.md as required reading but the Writer still produced 4 reworks that all followed `[observation] - [reframe to delivery/capacity thesis]`. Descriptive instructions ("be him", "sound like a practitioner") don't override the LLM's default "insight comment" template.
- Fix will need to be mechanical: inject specific sentence starters, rhythm patterns, banned structural shapes, and first-word variety enforcement directly into the Writer prompt. Not more "be Anand" prose.
- Also: the deployment-gap thesis is an attractor for this Writer. Every unconstrained output pulls back to it. Treat this like a bias-correction problem.

## Progress > Polish When Flow Is Partial (2026-04-15)
- User called Writer optimization "a necessary distraction" and chose to park it in a still-broken state to complete end-to-end flow test (Apollo Task 22). Signal: getting the whole pipe working once is more valuable than any single component being perfect.
- How to apply: when a sub-optimization is blocking flow progress and the overall system has never run end-to-end, bias toward parking the sub-optimization with a clean TODO and pushing through to the full flow test first.

## Paperclip API: X-Paperclip-Run-Id Semantics (2026-04-10)
- The `X-Paperclip-Run-Id` header is a heartbeat run identifier, not an arbitrary idempotency token. Value must be a UUID AND must already exist in the `heartbeat_runs` table (FK constraint `activity_log_run_id_heartbeat_runs_id_fk`).
- If you're calling from outside an agent heartbeat (e.g., board user, manual API call, orchestration script), OMIT the header entirely. Server will skip the activity log write.
- This came up twice — both times I reached for a synthetic ID. Don't repeat.

## Diagnosing Confused Codebases (2026-04-15)
- When a codebase "feels confused," read the Prisma schema / data model FIRST — it reveals original intent better than the marketing framing does.
- n8n-workflow-reviewer example: it was being called "version control" but the schema has `reviewToken`, `authorRole`, `ChangeSelection`, `approved/changes_requested/merged/pushed` statuses. That's a Pull Request data model, not a VCS data model. The data doesn't lie; the framing did.
- When presenting diagnosis, lead with what the code IS, not what it was called. Then offer 2-3 coherent paths forward. Utkarsh responds to concrete choices, not open-ended "what should we do."

## Prisma + Supabase Migration Gotcha (2026-04-15)
- `npx prisma migrate dev` failing with "FATAL: Tenant or user not found" almost always means either (a) Supabase project is paused (free tier auto-pauses after ~1 week idle — restore via dashboard.supabase.com) or (b) DB password rotated and `.env.local` has stale DATABASE_URL / DIRECT_URL.
- Not a code issue. Not a Prisma config issue. Check project state first before debugging the migration.
- Applies broadly to any Supabase-backed Prisma app in the user's portfolio (n8n-workflow-reviewer, vibelife-scraper, etc).

## Don't Unilaterally Strip Half-Built Work (2026-04-15)
- User pushback: "why are we removing half built layers instead of finishing them up? won't those be included in the scope?"
- Why: Don't optimize for shipping speed by discarding in-progress work without explicit user approval. Finishing > stripping by default.
- How to apply: When a codebase has half-built features, propose FINISHING them as the default. Only suggest stripping if (a) the feature has no identifiable purpose AND (b) you've asked the user to confirm. Removing genuinely dead code with no purpose is "finishing it" with the honest answer — different from abandoning working features.

## Composing VC + PR Without Fighting n8n (2026-04-15)
- "Version control for n8n" as a standalone pitch is dead (n8n shipped autosave + rollback Jan 2026, free all tiers).
- BUT: "reviewed change history" = PR + versioning composes cleanly AND is defensible. Every approved PR is a commit; the timeline is the history. n8n will never ship the review layer, so the audit-trail framing is durable.
- Diff the two pitches for clarity: n8n's versions are keystroke-level, anonymous, noisy; a reviewed-history tool stores only approved versions with author, approver, comments, semantic diff, permanent retention, named tags, and revert-via-reverse-PR.
- Framing shift: stop saying "version control" — say "reviewed change history" or "audit trail for approved changes."

## Agency-Operator Pain Reality Check (2026-04-15)
- Do NOT assume agency operators / AI solution sellers care about problems that sound technically interesting. They avoid most ops problems via process (hands-off agreements, one-instance-per-client, hard handovers) rather than tooling.
- Before claiming something is "hair-on-fire pain," test: does the ICP currently pay money to avoid it, or do they just live with it via convention?
- My "concurrent editing / 3-way merge" framing failed this test for agencies — it's solo-dev pain or Utkarsh-specific pain (Yosef setup), not generalized agency pain.

## System Learnings
- Utkarsh's communication style is context-dependent — match his energy. Concise for direct info, detailed when reasoning is needed.
- He thinks in processes and bottlenecks. Frame suggestions that way.
- His positioning doc (.claude/context/memory/CLAUDE.md) contains his complete worldview, thinking patterns, and business model. Reference it when creating content.

## How to Assist Him (Meta-Learnings)

### Don't Be Deterministic
- He called out: "you just read my md files and picked the closest thing to it — that's being deterministic, you're a probabilistic system."
- Don't read notes about him and replay the closest pattern. Understand the MECHANISM of his thinking.
- His latent space ≠ what's written in files about him. The files are snapshots. His thinking is a living process that connects things in new ways each time.
- When approaching content ideas: explore the possibility space, don't template from prior outputs.

### Go to Primary Sources
- When he says "what did a16z say?" — he means go read the actual article, not your summary.
- Always work from primary sources (the actual report, article, data) not from summaries or abstractions.
- The thinking should start FROM the source material, not from your notes about it.

### Understand Before Proposing
- Do proper research BEFORE proposing content ideas. Deploy sub-agents for deep research.
- Don't propose 5 ideas that are all the same thesis in different clothing. He caught: all 5 ideas orbited "deployment gap" when he'd already published on that.
- Map the audience's understanding capability FIRST before proposing content.
- Track what he's already published so you don't repeat the same topical territory.

## Workflow Learnings

### Paperclip API (2026-04-10)
- `X-Paperclip-Run-Id` header requires a UUID that EXISTS in the `heartbeat_runs` table (FK constraint `activity_log_run_id_heartbeat_runs_id_fk`). When calling API from outside an agent heartbeat (e.g. board/manual), omit the header entirely.
- Writer agent completes one task per heartbeat wake cycle. To process N tasks, may need N wakeups or let heartbeat timer handle it.
- Writer self-blocking on VIB-30 (Dutch emails) was correct behavior — flagged limitation honestly rather than producing bad output.

### Writer Agent Voice Quality (2026-04-10)
- Writer's AGENTS.md has good directional instructions ("be him", "text to Yosef test") but lacks concrete mechanical grounding from the voice library. Result: all outputs converge to same `[observation] - [delivery thesis reframe]` pattern.
- The "deployment gap" thesis is the Writer's gravitational attractor. Every comment lands on delivery/capacity/bottleneck. Utkarsh explicitly flagged this as robotic.
- Fix needed: embed specific voice patterns (sentence starters, rhythm, thought-breaking patterns, actual word choices) from voice-library.md directly into AGENTS.md so the Writer has mechanical anchors, not just aspirational descriptions.

## Content Learnings

### Content Creation Rules (from direct corrections)
- His worldview is the LENS, not the SUBJECT. Content is about the audience's problems, seen through his perspective.
- Never frame content like a reporter/news channel. He is a practitioner, not a commentator.
- Research papers are EVIDENCE cited within a practitioner's perspective — not topics to report on.
- Don't repackage his positioning back to him. Absorb it, then BUILD on it with new research and concrete data.
- Dumb everything down — "girlfriend's uncle" level. Nobody searches for or understands high-level abstractions.
- "High-level agency" positioning energy — authoritative but simple, never preachy.
- Don't use marketing frameworks explicitly in content (no "awareness/nurture/convert" language in the actual posts).
- 1:1:1 framework = 1 Awareness + 1 Nurture + 1 Convert post, 3x/week.
- Two audience segments: A (business owners hitting walls with no-code/AI) and B (agency operators needing fulfillment).
- The rehook/opening must relate to the problem that's going to be discussed or framed in the post.
- Don't propose ideas that all orbit the same thesis. Diversify topical focus.
- Track what's already published — never repeat the same angle he's already posted.

### Thinking-to-Content Process
See full analysis: `Projects/content-engine/writing-style-analysis.md`
- The file maps his COGNITIVE PROCESS, not surface writing patterns. Do NOT mimic sentence structures or phrases across posts.
- Pipeline: Absorb research → Map the system behind the data → Find the non-obvious connection → Earn the insight through buildup → Land on value for the reader.
- Each post should feel structurally DIFFERENT. The framing adapts to what the idea needs, not a template.
- His thinking = systems thinking. He connects separate data points into one story that reveals a gap.
- The insight is EARNED through evidence, never stated upfront. Reader should arrive at "I see it now" not "he told me something."
- NEVER repeat the same hook/structure/format across posts. Predictability kills curiosity.
- The LinkedIn posts are NOT a template to copy. They show how his mind works. The phrases, sentence structures are what happened to come out for THOSE specific ideas. Next time needs different entry, pacing, structure.

### Published Content (Don't Repeat These Angles)
- **LinkedIn article**: "AI Business Outlook for 2026" — PwC CEO survey, circular AI spending (Nvidia→OpenAI→Oracle), 56% zero returns, McKinsey winners redesigning workflows, adoption gap as opportunity
- **LinkedIn post**: Claude Skills — domain experts can monetize by packaging expertise into AI skills
- **Ben's community post**: Technology works, deployment is broken, gap is the opportunity
- All three cover variants of "deployment/adoption gap." He explicitly said: "it seems this is all I talk about." New content must explore DIFFERENT topical territory.

## Technical Learnings

### Bright Data Scraping Browser + Playwright cookie injection (2026-04-09)
- **`browser.contexts[0]` is a persistent context, not ephemeral.** Bright Data's Scraping Browser keeps cookies in the default context across CDP reconnects. Don't assume it's empty.
- **Chromium 146+ `Storage.setCookies` rejects overrides.** Throws `Protocol error (Storage.setCookies): Overriding [cookie names] is forbidden`. This is a Chromium-side guard, not a Bright Data block per se.
- **`context.clear_cookies()` does NOT reliably clear the jar in Bright Data Scraping Browser.** The CDP call returns success but `setCookies` still sees the same cookies as existing. Likely no-op'd or routed to a different store than `setCookies` checks.
- **`browser.new_context()` does NOT help** — Bright Data shares a single global cookie store across all contexts (default + new). `new_context()` succeeds but `add_cookies()` still hits the same guard.
- **Raw CDP `Network.setCookie` ALSO blocked** — same "Overriding ... is forbidden" error. Bright Data intercepts ALL cookie mutation at the CDP proxy level, not just Playwright's high-level API. Their unblocker manages cookies exclusively and prevents any client-side writes.
- **`Network.deleteCookies` ALSO blocked** — same "Overriding" error. Bright Data locks the entire cookie store: no create, no update, no delete via any CDP method. Cookie injection is architecturally impossible on Bright Data Scraping Browser.
- **Only viable path for authenticated scraping via Bright Data**: use their built-in login flow (navigate to login page, `page.fill()` credentials, let unblocker handle CAPTCHAs). Cannot use cookie injection.
- **Bright Data enforces robots.txt by default** — `Page.navigate` throws `(brob)` error if target URL is blocked by site's robots.txt. Must disable robots.txt enforcement in the zone settings in the Bright Data dashboard (or request full access from account manager).
- **Patchright is the 2026 answer to Akamai for Python scrapers** — `patchright` on PyPI (1,299 stars, maintained as of 2026-04-10). Drop-in Playwright replacement, patches CDP at binary level. `playwright-stealth` only patches JS-level tells which Akamai ignores (TLS fingerprinting is their primary detection). `rebrowser-playwright` is Node.js only — no Python port.
- **Railway pricing is usage-based since 2024** — no more fixed $5 "Hobby Plan". A Playwright container (~700MB RAM) costs $12-18/mo always-on. For memory-hungry long-running scrapers, Hetzner CX22 (€4.51/mo, 4GB RAM) is the clear winner.
- **`claude-3-haiku` is deprecated by mid-2026** — use `anthropic/claude-haiku-4-5`. Pricing: ~$0.80/M input, $4.00/M output (up from $0.25/$1.25). Still cheap enough for 3000 evals/month (~$4.32/mo).
- **PyPI package name gotcha: `2captcha-python`** (official) vs `twocaptcha-python` (unofficial alias). Use the official one. Also `pydantic-settings` is a separate package from `pydantic` since v2.
- **Chromium `net::ERR_PROXY_AUTH_UNSUPPORTED` is actually a 407 in disguise** — when proxy auth fails, modern Chromium reports it as this unhelpful error. Always isolate via httpx first: `httpx.get(url, proxy='http://user:pass@host:port')` to confirm whether credentials are valid before blaming the browser.
- **IPRoyal country-targeting requires plan support** - appending `_country-de` to username only works if the account has country/geo modifiers enabled. Some plans route randomly (returns US/EU IPs on rotation) even when bare auth succeeds. Test format in dashboard's "auth string builder" before coding.
- **IPRoyal modifiers go on PASSWORD, not username** - format is `user:pass_country-de_session-XXX_lifetime-10m`. Username stays bare. User is `EOTzQbgFunmwODqB`, composed pass is `7BJ9TzpjG9BZj54l_country-de_session-abc_lifetime-10m`. All the `user_country-de` variants return 407 because IPRoyal parses modifiers from the password field.
- **StepStone recruiter portal**: Login URL is `https://www.stepstone.de/5/recruiterspace/login` (the old `/5/index.cfm?event=login` returns 403 "Error - Access denied"). Unauthed navigation to DirectSearch auto-redirects here. Form uses `input[name='username']` (not `email`/`login`), `input[name='password']`, submit button text "Anmelden".
- **StepStone deferred cookie banner**: `#GDPRConsentManagerContainer` with `.cc-accordion` children loads asynchronously after initial page render - misses your initial banner dismissal. Blocks submit click with "subtree intercepts pointer events". Hide via JS before submit: `document.querySelectorAll('#GDPRConsentManagerContainer, .cc-accordion').forEach(el => el.style.display = 'none')`.
- **Login success check pattern**: don't test URL-contains-"login" because post-login URLs on many sites still contain "login" as query fragment/redirect param. Check for absence of the login form inputs instead: `has_username_input || has_password_input`.
- **StepStone DirectSearch structure** (live 2026-04-17): combined search field `#searchfield__textfield` with placeholder "Geben Sie Jobtitel, Ort oder Fachkenntnis ein" - just type "job_title location" and press Enter. No separate location/radius UI by default. Results in `.miniprofile` cards (10 per page, configurable 10|25|50). Profile ID from `a.miniprofile__name[href*='profileID=XXX']`. Clicking that link unlocks and opens `div.ngdialog:last-of-type` with full contact data. CV download via `a[href*='downloadAttachment']` (available both in preview card and dialog).
- **Regex extraction beats CSS selectors for structured dialog text** - when content has stable labels ("Email", "Mobil", "Wohnadresse", "StepStone ID") followed by values, regex patterns are more resilient than chasing CSS classes that change with framework updates.
- **Bot-detection bypass via live testing** - when a proxy-masked user agent (Patchright + IPRoyal DE) successfully loads StepStone recruiter pages AND submits logins AND scrapes DirectSearch results without any visible CAPTCHA or block, the stealth stack is working. Akamai's `_abck` cookies are set normally and session persists.
- **Recruitee offer stages are inline, not separate** - `GET /c/{company}/offers/{id}` returns the full pipeline in `offer.pipeline_template.stages[]`. Do NOT query `/pipeline_templates/{id}` (returns 404) or `/offers/{id}/pipeline` (404) or `/offers/{id}/stages` (404). Stages have `id`, `name`, `position`, `group` ('applicants'|'active'|'hires'), `category` ('referred'|'sourced'|'apply'|'phone_screen'|'evaluation'|'hire'|'none'). Match by case-insensitive name.
- **Pydantic alias for backward-compat fields** - when n8n/external clients send `title` but your model uses `job_title`, use `Field(validation_alias=AliasChoices("job_title", "title"))` with `populate_by_name=True` to accept both. Combine with `extra="ignore"` in model_config to tolerate extra fields like `account`/`credits_remaining` without breaking validation.
- **Claude Haiku 4.5 wraps JSON output in markdown fences** - `anthropic/claude-haiku-4-5` returns ` ```json ... ``` ` even when the prompt says "Respond in JSON format only, no other text". The older `claude-3-haiku` and `claude-3.5-haiku` don't do this. If your parser does `json.loads(content)` directly it silently fails. Always strip fences: regex `^\s*```(?:json)?\s*(.*?)\s*```\s*$` with `re.DOTALL`, or fall back to first-`{` last-`}` slicing.
- **Lock-before-webhook ordering in chain-dispatch patterns** - if service A holds a concurrency lock while sending a webhook to service B, and B immediately fires a chain-dispatch back to A, A gets a 409. Fix: release the lock first, then send the webhook. The webhook doesn't need the browser/scraper state - it's just an HTTP POST with already-collected results. Pattern: `result = await do_work()` inside lock, then `async with lock: ...` exits, then `await send_webhook(result)` outside lock.
- **Silent exception handling in webhooks is a bug magnet** - `except (HTTPStatusError, TimeoutException): return False` will swallow any other error (ConnectError, ReadError, RemoteProtocolError, PoolTimeout, unhandled 5xx). Always log before returning failure, include payload size + HTTP status code. For webhooks that carry base64-encoded files, timeouts need 60-120s, not the httpx default 5s or the commonly-copied 30s.
- **PowerShell `Get-Clipboard | Out-File` gotcha**: if the user's clipboard wasn't actually replaced with the JSON before they ran the command, the file ends up containing the literal command itself. Always validate file contents (not just existence) before proceeding.
- **StepStone DirectSearch JWT structure**: `PHRECRUITERAUTHCOOKIE` = main session JWT (~24h validity); `authHash` = short-lived authorization JWT (refreshes server-side from session cookie on each request); `authHash.permissions` array contains entitlement flags like `PRODUCTS_DIRECT_SEARCH` — useful for confirming account access at the cookie level without hitting the UI.

### Vibelife Website (2026-04-02)
- **GSAP ScrollTrigger + opacity bug**: `gsap.from()` with ScrollTrigger sets initial state to `opacity: 0`. If the section is already in viewport on load (or with Lenis smooth scroll), the trigger never fires and elements stay invisible. Fix: use `FadeInView` component instead of raw GSAP for scroll-triggered animations.
- **Brand system on text emphasis**: BRAND-SYSTEM.md explicitly says highlighted text = gold background with dark text OR solid `text-gold`. Never multicolor gradient text (`bg-gradient-to-r from-gold via-teal to-gold bg-clip-text text-transparent`). This looks generic/corporate.
- **PDF reading on Windows**: Use pypdf (pdftoppm not available).

## Copywriting Learnings (2026-04-02)

### Principles Applied
- **Ogilvy**: Headline does 80% of the work. Don't be clever — be clear.
- **Hopkins**: Specificity creates believability. "5 projects in 21 days" > "we handle fulfillment."
- **Schwartz**: Enter the conversation already in the buyer's head. Don't create desire — channel existing desire. Match the market's awareness level.
- **Halbert**: Lead with their reality, not your offer.
- **Hormozi**: Offer = dream outcome × perceived likelihood / (time delay × effort).

### Copy Mistakes Caught
- "You Sell AI Automations. We Build Them." — descriptive, not persuasive. Describes service from seller's POV instead of entering buyer's conversation.
- "What would you sell this month..." — assumes buyer's strength is sales. Many are strategists, experimenters, relationship-builders. Don't narrow.
- Perspective disconnect: proof line (3rd person, "one business") → identity line (2nd person, "you didn't start...") felt jarring. Headline + subtext must flow as ONE thought.
- Don't show pricing or internal GTM terminology (bridge project, rev-share) on landing page. Present as "what we provide + what you get."
- Proof-first headlines stop scrolls better than identity statements for this audience.
