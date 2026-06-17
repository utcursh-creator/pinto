---
type: reference
date: 2026-06-16
project: cricket-app
tags: [cricket-app, frontend, cricheroes, ia, design, research]
---

# CricHeroes frontend map + our minimalistic non-clone translation

Deep-research output (4 mappers + synthesis). Use this as the IA reference when designing our Flutter frontend slices. Full raw result: workflow run wf_565bf5e0-622.

## CricHeroes information architecture (what it actually is)
A content-dense sports super-app: persistent BOTTOM TAB BAR (Home, My Cricket, Feed, Market) + a LEFT HAMBURGER DRAWER that holds identity and ALL settings (there is no Profile tab). Onboarding is a linear stack: Splash/Country select -> phone/email -> 5-digit OTP -> Profile setup -> Home. Two spines: (1) PRODUCE a match (Start A Match -> teams -> match details -> Squad/XI -> toss -> openers -> one ball-by-ball scoring console with run pad, extras modifiers, WICKET, UNDO, per-ball edit); (2) CONSUME a match (TV-style live view: Live / Scorecard / Commentary / Wagon Wheel / Graphs / Info-Squad). Around the spine: Looking-For matchmaking, editorial Feed, Market/Store, and a gamified Player Profile (Stats/Awards/Badges/Teams/leaderboards) behind a PRO paywall. Brand = red/crimson, high-saturation, ad-heavy, tabs-within-tabs.

## Our minimal app = ~15 screens across 5 slices (all backend-supported)
- **App Foundation**: two-button sign-in (Google/Apple); 2-3 tab shell (NOT 4+drawer); Home = your matches + Start-a-match.
- **Identity UI**: Create/Edit Profile; Player Profile (teams + match appearances); My Teams + roster (search / guest / invite-link / claim).
- **Match Setup UI**: linear wizard - teams -> details (smart ICC defaults, advanced toggles hidden) -> XI -> toss (optional flip) -> openers.
- **Scoring UI**: one console - context header; run pad + extras + wicket; dismissal flow (common-first); this-over strip + first-class undo/edit/delete/insert; optional wagon-wheel tap; engine-driven over/innings/result.
- **Live Scorecard UI**: public TV-style live header; unified full scorecard (live AND finished from one fold); lean charts tab (Manhattan / worm / run-rate / partnerships / wagon wheel).

## Deliberately DROPPED (rip-off avoidance + scope honesty)
Feed, Market/Store, Looking-For matchmaking, Find-Friends/contact-sync, bulk import, career/aggregate stats, awards/badges/leaderboards, MVP/AI-insights, PRO paywall, ALL ads, rendered share-images, officials, tournaments. Most are unbuildable today anyway (no Stats/Social/Tournaments backend).

## Anti-clone design principles
1. Single restrained accent, explicitly NOT red/crimson, on neutral greys.
2. Radically lower density: one job per screen, whitespace, progressive disclosure (vs tabs-within-tabs).
3. Zero monetization chrome: no ads, no PRO banners; scoring + charts all free (their #1 reviewer complaint).
4. Spelled-out, sentence-case language ("Right-hand bat", not "RHB RM"); no ALL-CAPS.
5. Flat, restrained data-viz: thin lines, muted fills, one chart theme (not glossy/skeuomorphic).
6. One consistent thin-stroke icon set, flat and labeled.
7. Identity = OAuth account, not phone: no country-gate / OTP boxes / PIN / WhatsApp login - one two-button sign-in (structurally different onboarding).
8. Identity/settings a first-class destination (Profile tab or header avatar), not a hamburger drawer.
9. Scope honesty: only build screens our backend can serve; do not fake stats/awards/feeds/matchmaking/market/share-images.
10. Lean on real backend strengths as UX: engine-owned strike rotation, first-class re-folding corrections (undo/edit/delete/insert any past ball), login-free public live viewing.

## Open product decisions (PENDING - user dismissed the question prompt 2026-06-16; revisit)
1. Navigation shape: 2-tab (Home+Profile) [rec] vs 3-tab (+Teams) vs 1-home+header-avatar.
2. Player Profile honesty: teams + match-appearances only [rec] vs "stats coming soon" placeholders vs pull Stats sub-project forward.
3. Wagon-wheel capture default: OFF/opt-in per match [rec] vs ON.
4. Live commentary: auto templated event-line per ball [rec] vs dedicated Commentary tab (needs a generation layer).
5. Sharing/virality: accept v1 with only a public live-match link [rec] vs build rendered share-images (Social sub-project).
6. Toss: optional subtle coin flip [rec] vs drop animation entirely (backend only needs the result).
