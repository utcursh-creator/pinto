---
type: session-log
date: 2026-04-02
time: "22:00"
topics: [vibelife-website, brand-system, copy, gtm-strategy, landing-page, visual-design]
projects: [vibelife-website, gtm-strategy]
outcome: Fixed brand violations, replaced video section, landed new hero copy, defined full landing page structure aligned to GTM playbook
---

# Session: 2026-04-02 22:00 — Vibelife Website Redesign + GTM Pivot

## Quick Reference
**Topics:** brand system enforcement, gradient removal, video section replacement, hero copy iteration, GTM-aligned landing page structure
**Projects:** vibelife-website, gtm-strategy
**Outcome:** Fixed 11 files with brand violations (gradient text), replaced video section with before/after case studies, scaled down FinalCTA, iterated hero copy 7+ rounds to proof-first approach, defined full new landing page structure based on 90-day GTM playbook
**Duration:** ~3 hours

## Decisions Made
- **Remove ALL multicolor gradient text** — `bg-gradient-to-r from-gold via-teal to-gold bg-clip-text text-transparent` violates BRAND-SYSTEM.md. Replaced with solid `text-gold` or `text-teal` per brand color usage rules. Gold glows on dark backgrounds naturally.
- **Replace video section with before/after case studies** — Marketing explainer video didn't add value and felt "corporate." Replaced with 3 transformation cards (AI BDR, Content Engine, Client Reporting) showing before/after with metrics.
- **Scale down FinalCTA** — Was `text-display-xl` (128px), now `text-display` (72px). Removed `min-h-screen`, reduced spheres, sentence case instead of ALL CAPS.
- **Major positioning pivot** — Current site addresses wrong awareness level. Buyer has ALREADY embraced AI, doesn't fear replacement. They fear they can't DELIVER what they've sold. Entire landing page needs to reframe around fulfillment bottleneck.
- **Hero copy (APPROVED):**
  - Eyebrow: `FOR AI AUTOMATION BUSINESSES`
  - Headline: "We cleared 5 projects for one business in 21 days and they never touched fulfillment again"
  - Subtext: "If you're stuck building everything yourself we should probably talk"
- **Offer framing** — 3-week sandbox presented as "what we provide + what you get." NO pricing on landing page. NO internal terminology (bridge project, rev-share).
- **Eyebrow uses "businesses" not "agencies"** — broader, less pigeonholing
- **Landing page structure (APPROVED):** Hero → Proof Bar → Problem → Sandbox Offer → Before/After → Trust/Objections → CTA

## Key Learnings
- **GSAP ScrollTrigger + opacity bug**: `gsap.from` with ScrollTrigger sets elements to `opacity: 0` before trigger fires. If section is in view on load (or with Lenis smooth scroll), elements stay invisible forever. Fix: use `FadeInView` component instead.
- **Brand system on text emphasis**: BRAND-SYSTEM.md explicitly says "Highlighted text: Gold background with #18140E text and border-radius 6-8px" OR solid `text-gold`. Never multicolor gradient on text.
- **Copy awareness level mismatch**: "AI Doesn't Replace Your Expertise. It Multiplies It." addresses a fear the buyer has already moved past. These are agency owners already selling AI — they fear they can't deliver, not that AI will replace them.
- **Copy principles applied this session**:
  - Ogilvy: headline does 80% of the work
  - Hopkins: specificity creates believability ("5 projects, 21 days" > "we handle fulfillment")
  - Schwartz: enter the conversation already in their head, don't create desire
  - Halbert: lead with their reality, not your offer
- **Don't assume buyer's strength is sales** — they could be strategists, experimenters, relationship-builders. "What would you sell" is too narrow.
- **Headline + subtext must flow as one thought** — no jarring perspective shifts (3rd person proof → 2nd person identity = disconnect). The "you" must be earned by the proof.
- **Proof-first headlines stop scrolls better than identity statements** for this audience.

## Solutions & Fixes
- **Gradient text brand violation** → Replaced all 11 instances of `bg-gradient-to-r ... bg-clip-text text-transparent` with solid `text-gold` or `text-teal`
- **Video section not adding value** → Replaced FounderSection (200+ lines custom video player) with before/after transformation cards using FadeInView
- **FinalCTA text too large/painful** → Scaled from display-xl to display, removed min-h-screen, reduced sphere sizes
- **FounderSection cards invisible** → GSAP ScrollTrigger holding cards at opacity:0. Switched to FadeInView component.

## Files Modified
- `app/src/components/sections/NewHeroSection.tsx` — gradient text → solid text-gold, text-ink-3 → text-ink
- `app/src/components/layout/NewNavbar.tsx` — logo gradient → solid text-gold
- `app/src/components/sections/FooterSection.tsx` — logo gradient → solid text-gold
- `app/src/components/sections/ForwardDeployedSection.tsx` — gradient → solid text-gold
- `app/src/components/sections/FounderSection.tsx` — COMPLETE REWRITE: video player → before/after case studies with FadeInView
- `app/src/components/sections/FinalCTASection.tsx` — scaled down text, removed min-h-screen, smaller spheres
- `app/src/components/sections/ProblemSection.tsx` — gradient → solid text-gold
- `app/src/components/sections/SandboxSection.tsx` — gradient → solid text-teal
- `app/src/pages/WhatWeBuildPage.tsx` — gradient → solid text-gold
- `app/src/pages/HowItWorksPage.tsx` — gradient → solid text-gold
- `app/src/pages/ResourcesPage.tsx` — gradient → solid text-gold

## Pending Tasks
- [ ] Implement full landing page rewrite (hero, proof bar, problem, sandbox offer, before/after, trust, CTA) based on approved structure + GTM playbook
- [ ] Fix cursor (user says it's not smooth)
- [ ] Update Brand Bible with GTM playbook content (90-day plan, ICP refinement to $10-20K MRR, offer framing)
- [ ] Update secondary pages (How It Works, What We Build, Resources) to match new positioning
- [ ] YouTube GTM strategy docs (parked — Task 2 for future session)
- [ ] Remotion video concept for website (when ready to produce)

## Errors & Workarounds
- **FounderSection blank on render** — GSAP `gsap.from` sets initial state to opacity:0, ScrollTrigger hadn't fired. Fixed by switching to FadeInView component which handles viewport detection reliably with Lenis smooth scroll.
- **Build errors from unused imports** — Previous session had `motion` import in WhatWeBuildPage.tsx causing TS6133. Already fixed.

---

## Raw Session Summary

Session continued from a previous conversation where Phases 1-7 of a visual redesign were complete and the full site had been restructured from 12 pages to 4 pages.

**Phase 1: Brand system enforcement.** User sent screenshot showing hero and expressed strong dislike of multicolor gradient text on "Replace", "It Multiplies It.", and "VibeLife" logo. Said it looked "very corporate and generic" like "old blue label type websites." Read BRAND-SYSTEM.md, found the system explicitly prescribes solid gold text or gold highlight backgrounds — never multicolor gradients on text. Fixed all 11 instances across the codebase.

**Phase 2: Video section replacement.** User said the video section "doesn't make sense" and was "made from a marketing point of view." Proposed 4 alternatives. User liked before/after case studies approach. Replaced the entire FounderSection (200+ line custom video player) with 3 transformation cards (AI BDR, Content Engine, Client Reporting). Hit a bug where cards were invisible due to GSAP ScrollTrigger opacity issue — fixed by switching to FadeInView.

**Phase 3: FinalCTA scaling.** User said text was "very big and hurts eyes." Scaled headline from display-xl (128px) to display (72px), removed min-h-screen, reduced sphere sizes, switched to sentence case.

**Phase 4: Strategic pivot.** User shared a comprehensive 90-day GTM playbook targeting AI automation agency/business owners at $10-20K MRR. This revealed the current website is one full awareness level behind the actual buyer. The site talks about "AI doesn't replace your expertise" but these buyers have ALREADY embraced AI — they fear they can't deliver what they've sold. User asked for full landing page restructure.

**Phase 5: Hero copy iteration (7+ rounds).** Started with "You Sell AI Automations. We Build Them." — user rejected as bad copy, said to study greatest copywriters. Proposed 3 concepts based on Ogilvy/Schwartz/Hopkins/Halbert principles. User liked Concept C (specific proof) + Concept A (question). Through iteration: flipped title/subtext order, changed "agency" to "business", broadened from "sell" to general capability, fixed perspective disconnect between proof (3rd person) and identity (2nd person), shortened for natural flow. Final approved hero:
- Headline: "We cleared 5 projects for one business in 21 days and they never touched fulfillment again"
- Subtext: "If you're stuck building everything yourself we should probably talk"

**Phase 6: Offer section reframing.** User rejected showing pricing ($3-7.5K) or internal terminology (bridge project, rev-share) on landing page. Reframed as "3-Week Sandbox" with "what we provide + what you get."

User also mentioned wanting to use YouTube as primary distribution channel ($10K/mo monetization goal), cross-posting to Reddit and communities. Wants raw Remotion-powered videos using brand design system. This is parked as Task 2 for a future session.

User requested /compress before implementation to preserve all decisions and create implementation plan. Also noted cursor needs fixing (not smooth).
