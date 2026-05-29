---
type: memory
category: preferences
last_updated: 2026-03-11
---

# User Preferences

## Engineering Preferences (2026-04-15)
- **NO custom middleware.** If an OSS library exists, use it. Don't rebuild auth/capture/encode/render glue from scratch.
- **Top-notch stack only.** No workarounds, no hacks. If quality/functionality WILL be compromised by a choice, surface it explicitly - don't hide trade-offs.
- Implication: prefer battle-tested crates with high stars/active maintenance over hand-rolled code, even if the crate is slightly heavier.

## Writing Preferences (2026-04-17)
- **NEVER use em dashes (—).** Use regular hyphens (-) instead, in all output, code comments, and documentation.
- Reason: explicit user rule stated in Aramas scraper plan.
- How to apply: applies to all future work. When writing prose, use commas, semicolons, or colons where an em dash would normally go. For CLI/code output, use `-` or `:`.

## GTM / Distribution Preferences (2026-05-28)
- **No LinkedIn engagement-farming loop.** User explicitly rejects LinkedIn as a GTM channel because it pulls toward content-creation-and-engagement-farming, which eats bandwidth they don't have. When designing distribution or outreach, do not propose LinkedIn-centric strategies. Email + tech-leveraged prospecting is the validated path.
- **Bandwidth is the binding constraint.** Default to low-cognitive-load paths. Don't propose multi-month commitments unless explicitly scoped as long-term.

## Build / Working Style (2026-05-28)
- **Rigorous incremental loop**: for each step, write code → test → audit → fix → redo, THEN move to next step. Never assume "done". Stay skeptical and curious, actively hunt for gaps and oversights. (Maps to TDD + verification-before-completion + code-review + systematic-debugging.)
- Wants superpowers skills used interchangeably/fluidly during a build, not rigidly.
- Plan-first: spec (PRD) before plan, plan before code.

## Tooling / Spend Preferences (2026-05-28)
- **LLM access = OpenRouter key (NOT Anthropic SDK direct).** Use OpenRouter for all LLM calls in his projects (claude-haiku-4-5 is his go-to cheap model, matches the Aramas scraper setup).
- **Reluctant to spend on tooling, especially during dev/testing.** Default to free tiers and open-source. Surface paid options as deferred "spend only if it proves necessary" decisions, not upfront requirements. He'll pay later for proven value, not for unvalidated setup.

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
