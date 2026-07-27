---
type: memory
category: preferences
last_updated: 2026-06-27
---

# User Preferences

## Engineering Preferences (2026-04-15)
- **NO custom middleware.** If an OSS library exists, use it. Don't rebuild auth/capture/encode/render glue from scratch.
- **Top-notch stack only.** No workarounds, no hacks. If quality/functionality WILL be compromised by a choice, surface it explicitly - don't hide trade-offs.
- Implication: prefer battle-tested crates with high stars/active maintenance over hand-rolled code, even if the crate is slightly heavier.

### App-build addendum (2026-06-12, cricket app)
- **NO vibe coding.** Disciplined spec → plan → TDD → verify, every step. Reaffirmed explicitly.
- **OSS / pre-built first, aggressively.** Lean on managed + open-source (Supabase, pgTAP, established Flutter packages) over anything hand-rolled.
- **Backend before frontend.** For app builds, design + build + test the backend as a verifiable unit FIRST; UI/frontend comes after. (He'll say when to move to UI.)
- **Verify external/pricing/library claims before asserting** — caught a real mistake assuming Firebase Phone Auth was cheap (it's ~6x pricier in India). Use research/verification workflows for load-bearing technical claims rather than memory.

## Proactively know the TRUE build state - don't under-scope "what's remaining" (2026-06-25, user feedback - IMPORTANT)
- After finishing the Stats sub-project I casually said "Tournaments is what's remaining" and offered to start push/store next. The user pushed back hard: before push-notifications (#61) / store-packaging (#62) / push-to-PR (#33), I must FIRST ensure everything already built is "fully built + tested + wired + not vibe-coded", and that there is MORE remaining than just Tournaments. Verbatim: "youre saying tournaments is what is remaining, idts - theres more, do a deep analysis and im not supposed to be saying all this to you you shouldve done this before hand".
- **The expectation: I should already KNOW the true completeness state of the whole app (gaps, stubs, orphaned backend capability with no UI, untested surfaces) and surface it proactively - not hand-wave a one-line "what's next" and not wait to be told to audit.** Calibration must be code-grounded, not optimistic.
- **How to apply**: before proposing next-phase work, run a real audit (backend health, frontend dead-ends, backend<->frontend wiring, test coverage, deferred inventory, spec-vs-built) and present the honest consolidated state FIRST. Sequencing rule the user wants: consolidate + finish + test + wire EVERYTHING already started BEFORE moving to new credential-boundary work (push/store/PR). Ties to the existing "feature-complete != shippable - calibrate explicitly" learning.

## UI / Visual Output Preferences (2026-06-17)
- **User runs on a DARK theme.** show_widget output that relies on `var(--color-background-*)` / `var(--color-text-*)` CSS variables INVERTS on dark mode -> panels go dark, text disappears.
- **Rule for show_widget mockups**: lock to EXPLICIT light-theme colors (#FFFFFF panel bg, #1A1A18 text, #6E6B62 mut, #F4F2EB cards, #FAF8F2 headers, #D4D1C7 borders, #FAFAF7 fields). The OUTER `.cat` surface can be `#EFEDE6` warm gray for the "mockups-on-a-sheet" feel. Brand colors (teal #0F6E56, amber flairs, dark score #0F2E26) stay explicit.
- Why: caught the first time when 3-panel widget was unreadable on his screen.
- How to apply: any visualize MCP mockup widget, always. Theme vars OK for inert text-only viz; never for mockup contrast.

## Verification discipline for app dev (2026-06-17, user feedback - IMPORTANT)
- When developing / integrating / wiring frontend<->backend, **actually RUN it and exercise the real flow on the TARGET platform**, not just analyze + one-platform widget tests. The user hit a "No Material widget" crash on the iOS sign-in screen that my Android-default widget tests never caught.
- **Test BOTH platforms**: Flutter widget tests default to TargetPlatform.android. Any screen using platform-adaptive chrome MUST also be tested under `debugDefaultTargetPlatformOverride = TargetPlatform.iOS` (and ideally rendered on the iOS simulator) before claiming it's verified. iOS uses Cupertino scaffolds which behave differently (e.g. no Material ancestor).
- Verb the user used: "this is not the way you're supposed to do it" - i.e. don't claim a screen works from analyze + happy-path Android tests alone; drive the actual running app on the platform they use (iOS). The user is on the iOS simulator.
- Practical loop now: build -> analyze -> widget tests on BOTH platforms -> rebuild iOS + render the actual screen(s) on the sim (screenshot, incl. forms/inputs) -> only then call it verified.
- **DO NOT control the user's computer (no computer-use / desktop puppeting) to verify (2026-06-19).** User stopped me mid-Simulator-driving: "I don't want you to use my computer." The right way to exercise the running app is a Flutter `integration_test` driven via `flutter drive` on the sim (boots the real app, taps through programmatically against live local Supabase, writes screenshots to /tmp/pitch_shots that I then Read). Capturing the sim framebuffer with `xcrun simctl io screenshot` is fine; taking over the mouse/keyboard/Simulator window is NOT.

## Writing Preferences (2026-04-17)
- **NEVER use em dashes (—).** Use regular hyphens (-) instead, in all output, code comments, and documentation.
- Reason: explicit user rule stated in Aramas scraper plan.
- How to apply: applies to all future work. When writing prose, use commas, semicolons, or colons where an em dash would normally go. For CLI/code output, use `-` or `:`.

## GTM / Distribution Preferences (2026-05-28)
- **No LinkedIn engagement-farming loop.** User explicitly rejects LinkedIn as a GTM channel because it pulls toward content-creation-and-engagement-farming, which eats bandwidth they don't have. When designing distribution or outreach, do not propose LinkedIn-centric strategies. Email + tech-leveraged prospecting is the validated path.
- **Bandwidth is the binding constraint.** Default to low-cognitive-load paths. Don't propose multi-month commitments unless explicitly scoped as long-term.

## Map-everything-before-rebuilding for big fixes (2026-07-01, cricket - IMPORTANT)
- When a build is found to be deeply broken (the cricket app's core loop failed a friend cold-test), the user does NOT want incremental patch-by-patch fixing. Verbatim: "analyze more deeply you will find more errors of such magnitude, i want everything mapped out before we begin - this will be the last time we will be doing - we have learnt a lot lets use all of it to develop this."
- **How to apply:** for a major remediation, FIRST produce an exhaustive, code-grounded defect map (every area + adversarial sweep: cricket-rules correctness, security/RLS, realtime, missing whole features, dead-ends) and a complete slice-by-slice rebuild plan; review it WITH the user; THEN execute once, properly. Do not start coding fixes until the full map + plan is agreed. Treat it as the definitive do-it-right pass.
- Reinforces the existing proactive-deep-audit expectation and the "feature-complete != shippable" calibration rule. The trigger for this was my seeded-data/provider-override testing giving false confidence (see learnings).

## Build / Working Style (2026-05-28)
- **Rigorous incremental loop**: for each step, write code → test → audit → fix → redo, THEN move to next step. Never assume "done". Stay skeptical and curious, actively hunt for gaps and oversights. (Maps to TDD + verification-before-completion + code-review + systematic-debugging.)
- Wants superpowers skills used interchangeably/fluidly during a build, not rigidly.
- Plan-first: spec (PRD) before plan, plan before code.

## Tooling / Spend Preferences (2026-05-28)
- **LLM access = OpenRouter key (NOT Anthropic SDK direct).** Use OpenRouter for all LLM calls in his projects (claude-haiku-4-5 is his go-to cheap model, matches the Aramas scraper setup).
- **Reluctant to spend on tooling, especially during dev/testing.** Default to free tiers and open-source. Surface paid options as deferred "spend only if it proves necessary" decisions, not upfront requirements. He'll pay later for proven value, not for unvalidated setup.

## Secrets / credentials handling (2026-06-27, cricket app)
- **When the user hands over keys (Supabase service_role/anon, OAuth client secrets, access tokens), keep them in GITIGNORED files, never commit them, and never echo them in plain output.** For the cricket app: `backend/.env.hosted` (access token) + `app/hosted_defines.json` (anon key + web client id).
- **The user said his keys are "all under protected environments... we don't need to rotate any key."** So do NOT keep nagging about rotation or "you exposed a secret" once he's chosen to share one in our protected workflow. Respect his stated risk posture; still keep the mechanical hygiene (gitignore, don't echo) by default.
- **Spend posture for shipping**: free tiers first. He wants to share the app with friends for real testing WITHOUT paying - so the Android sideload APK (free) is the priority path; the Apple Developer Program ($99/yr, needed for TestFlight/iOS sharing) and the Play Console ($25) are deferred "only when it proves necessary" spends.

## Content Tone + Substance (2026-05-29)
- **Substance spine = process optimization / process automation** with concrete measurable outcomes (time saved, cost saved) from his REAL builds. Lead with proof/value, not theory.
- **Tone: NOT attacking or competitor-bashing.** Rejected "your last automation partner built what you asked for, not what you needed" as too vague + too aggressive. Avoid attack-the-prospect's-past-vendor framing.
- **Content model = intertwine proof + distribution**: real build outcomes (proof of competence) woven with frontier-AI contrarian flavor (the engaging hook), so each piece both spreads AND demonstrates capability.

## GTM Direction: Content-Led Inbound (2026-05-29)
- **User's true preference is content-led INBOUND, not outbound prospecting.** Stated explicitly: "I never wanted to go towards a job board type of thing in the first place." Validated by data (job-board scraping returned 0 ICP-fit prospects). Outbound was tried + scratched.
- "Not too against content creation" IF some of it is automated. The hook is: build a partly-automated content pipeline so the bandwidth cost is low.
- When this user circles back to content/distribution (happened 3x in one session), that IS the signal of what they actually want to build. Support it; help them commit rather than re-litigate.

## Platform Psychology (2026-05-28)
- **LinkedIn is psychologically toxic for user.** His thinking inherently rejects it: too many pretenders, all personal-branding theater, "can't say real stuff." The burnout he associates with GTM is partly platform-driven (LinkedIn specifically). Do NOT route GTM through LinkedIn.
- **Twitter/X is his preferred platform.** Better for both spreading knowledge and taking it in. This is where he's willing to build presence.
- **Content format: TEXT + GRAPHICS only. NOT video.** Threads + supporting images/visuals. No video production (no ComfyUI video pipeline, no faceless-video channel for the Twitter play).
- **Content angle**: contrarian business-relevant insights (NOT tech info) extracted/translated from research papers, VC/YC/AI-convention sources, AI news. Digestible nuggets for a business/agency-operator audience (his ICP).

## Terminology Preferences (2026-05-28)
- **Use "process automations" NOT "AI automation"** when describing what user does or what prospects buy. User has observed "process automations" is more appealing in job posts and prospect language.
- **Use "custom automation development" NOT "custom integration"** when describing service category.
- **Preferred role-tier keywords for prospect-finding**: "Automation Partner", "Process Automation Engineer", "AI Automation Partner", "Forward Deployed Engineer", "CTO". These target strategic-tier hires, not contract labor.

## Identity
- **Name**: Anand Utkarsh (goes by Utkarsh)
- **Role**: Founder — Forward Deployed AI Partner
- **Positioning**: Full-cycle ownership from architecture to adoption. Not a freelancer, not a dev shop. The person who takes an AI tool from "it works" to "the business runs on it."
- **How he wants to be perceived**: Practitioner with depth. Someone who reads widely, thinks in systems, and shares what he finds with people he respects. High-level agency energy — authoritative but simple, never preachy or guru-like. The reader should think: "This person sees something I don't."

## The Offer (Updated 2026-04-02)
- **Positioning**: Fulfillment partner for AI automation businesses
- **Micro offer**: 3-week sandbox. Audit backlog → pick 2-5 most urgent builds → deliver in their tools → document everything → support until adoption.
- **Macro offer**: Ongoing fulfillment partnership. You sell. We build. They use it.
- **Content positioning**: Content creates the gap, the reader connects that Utkarsh fills it. Never pitch in content.
- **Key differentiator**: Full-cycle ownership — build + document + adopt. Not build-and-bounce. The finish line is adoption, not delivery.
- **No pricing on landing page** — discovery call handles that.

## ICP — Three Segments (Updated 2026-04-02)

### Segment A: AI Automation Agencies
- 1-5 person teams, $10-20K MRR, trying to break $30K+
- Can sell. Can't deliver fast enough. Backlog growing. Freelancers ghosting.
- Their internal monologue: "I'm turning down projects" / "I'm doing all the fulfillment myself"
- Geography: US, UK, Australia, Canada + **EU (especially Germany)** — German discipline + Utkarsh's logic = strong fit

### Segment B: AI Content Creator Businesses
- Have distribution (audience, community, content reach) but need fulfillment capacity
- People like Ben Van Sprundel's graduates — they learned to sell AI services but can't deliver at quality
- Yosef also fits here — has distribution, needs build capacity
- Their internal monologue: "I'm selling more than I can build" / "I tried hiring a freelancer and the work came back wrong"
- Utkarsh is the build-deploy-adopt layer behind their sales

### Segment C: Business Owners (Secondary)
- Running businesses with real processes, have domain expertise
- Using AI tools and hitting walls at scale. NOT tech-savvy — operators, not developers.
- Want to integrate AI into existing operations or productize domain expertise
- Lower priority than A and B for GTM

## Communication Style
- Context-dependent: concise when information is direct, detailed with reasoning when POV is needed
- Match his energy — don't over-explain simple things, but think out loud when reasoning matters
- Prefers direct, honest communication. No fluff.
- Uses contrarian structure naturally: what people believe → what actually happens → what it means
- When he corrects you, it's teaching. Absorb and internalize, don't just acknowledge.

## How He Thinks (Latent Space)
- **Systems thinker**: He doesn't see isolated data points. He sees flows — where money moves, where value gets created, where it gets stuck. He connects separate things into one story.
- **Pattern recognition across domains**: When he sees a16z's cost data, he doesn't think "AI is cheap." He traces what happens to markets when a core input goes to zero. He maps across industries, across time periods, across analogous shifts.
- **Gap identification**: Every system he maps reveals a gap — between supply and demand, between access and adoption, between perception and reality. The gap is always where the insight lives.
- **NOT deterministic**: Don't read his files and replay the closest pattern. Think probabilistically — explore the possibility space of what a connection could become. Understand the MECHANISM of his thinking, not the outputs.
- **Primary sources first**: He wants you to go to what a16z/McKinsey/researchers ACTUALLY said, then think from there. Not from summaries or abstractions.

## Work Style
- Full-stack operator: sales, marketing, building, ops, content, support
- Tool follows the problem — not platform-locked
- Tech stack: n8n, Make, custom code, API integrations, Supabase, PostgreSQL, code/lowcode/vibecode
- Architecture-first: validates system design before building
- Thinks in processes and bottlenecks, not features

## Full Skill Stack (Context — NOT sold as separate services)
These are how he adds value within partnerships, not standalone offers:
- **Brand visibility & conversion**: Good taste for design, making sure the visitor buys. Can increase brand perception.
- **Sales support**: Can help partners close, not just build what they sold
- **Business process design**: Maps operations, finds bottlenecks, designs systems
- **Fulfillment building**: The core offer — n8n, Make, Zapier, custom builds
- These compound when working with partners who have distribution (Segments A & B)

## Current Pain Points
- Doing too many things simultaneously — needs structure
- Inconsistency (especially LinkedIn posting)
- Needs a qualifying mechanism to decide what gets attention today
- Risk of burnout from context-switching across too many fronts
- Can't get sales meetings booked — JTM strategy is the response to this

## Task Management Preferences
- Wants clear daily priorities (not endless lists)
- Needs execution schema — what to work on, when, and why
- Values weekly reviews to check alignment between work and goals

## Review / audit expectations (2026-07-07)
- When the user says "attack it from all fronts", they mean an ADVERSARIAL, evidence-backed penetration review - not a tidy summary. Deliver the full enumerated list (they explicitly accept "even if there are 100 things to fix"), persisted as a project doc, then fix in order.
- They chose "everything, straight down the severity list" over a triaged release-gate subset. Do not silently narrow scope to the urgent items.
- Tell them plainly when a request is technically impossible as stated (shadcn/ui in Flutter) - flag it in a sentence, offer the nearest real thing, and let them pick. They picked the honest option immediately.
- Own regressions in your own recent work explicitly and without hedging. Several of the worst findings came from the sweep I had just called "verified"; naming that directly is expected.
- Separate what is ON THEM from what is on me (hosted push, credential rotation, store accounts) - they ask "what's on me now?" and want a short, concrete list.
- **"Don't stop" means ARM A LOOP, not just work longer.** The user escalated twice about stopping between turns. For long multi-unit work, use /loop dynamic mode (ScheduleWakeup at the end of each turn) so progress continues without them prompting, and report per-unit rather than asking what to do next.
- They want the iOS simulator actually driven as a user would: tournament flow, finding a team, finding/adding players - verified by me, not described.

## Working with them on Pitch (2026-07-07, reinforced repeatedly)
- **"Don't stop" is literal.** They have said it four times, with visible
  frustration at turn boundaries. Always end a turn by re-arming `/loop`
  (ScheduleWakeup) unless told to stop. Never end with "shall I continue?".
- **They do not want a summary of options; they want the work done and reported.**
  Report per unit with the gate numbers, then keep going.
- **They expect the simulator to be DRIVEN, not described.** "Adding the players
  and all of those things needs to be done by and verified BY YOU." Screenshots
  are the evidence; read them, don't just check the exit code.
- **They assume more defects remain and have been right every single time.** The
  8-slice rebuild was declared done, then a 10-agent audit rejected it, then a
  100-finding review found more, then the device found a crash none of it caught.
  Treat "it passes" as provisional.
- **They want the root fixed, not the symptom** ("every emerging issue from the
  roots of it must be fixed"). A patch that relocates a bug is a failure - and I
  did that twice on one crash before finding the class.
- **Honesty is load-bearing.** They react well to plainly stated mistakes
  (unfounded claims, wrong fixes) and badly to confident summaries that turn out
  hollow. State corrections without hedging or over-apologising.
- **shadcn/ui**: they asked for it for the UI. It is React+Tailwind and cannot run
  in Flutter; what ports is its composition discipline (semantic tokens,
  Skeleton/Empty/Alert/Field/ToggleGroup). They accepted that framing. They also
  have a genuinely web deliverable pending: pitch.app/privacy + /terms.

