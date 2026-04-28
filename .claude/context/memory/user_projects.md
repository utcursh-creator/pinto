---
type: memory
category: projects
last_updated: 2026-02-26
---

# Active Projects

## 1. Yosef Client Work
- **Status**: Active — primary revenue source
- **What**: Building AI automations for Yosef and his clients
- **Relationship**: Yosef is a client/partner — Utkarsh operates as his Forward Deployed Dev Team
- **Model**: Yosef runs sales → warm leads → Yosef scopes → Utkarsh builds → Utkarsh gets MONTHLY RETAINER
- **Real client projects built**: Marcel Keller (real estate presentation generator, 2-4h→10min), Poosch (SEO report generator, 45min→45sec), Egroma (WhatsApp construction reporting, 53 clients 292 workers, self-hosted Hetzner+GDPR), Bildungsfabrik (IHK thesis assistant in LMS), Aramaz Digital (StepStone candidate sourcing, replaced 4h/day recruiter work)
- **Stack**: n8n, Make, Supabase, PostgreSQL, Hetzner, Mistral, OpenAI, Pinecone, vector DBs, Patchright, custom FastAPI scrapers — enterprise-grade, not simple Zapier work
- **Revenue**: $1,500/month retainer, going to $2,000 in 3 months. UNDERPRICED relative to value delivered. Utkarsh doesn't know Yosef's client-side pricing.
- **Yosef doesn't share economics**: Utkarsh should have a direct conversation (not "slip it in") — needed to set correct pricing for next partnerships

## 2. Content Engine
- **Status**: Active — needs consistency
- **What**: Creating and distributing content across two channels
- **Channels**:
  - **Ben's AI Accelerator Community** (benai.co) — Posting content inside Ben Van Sprundel's community. Ben runs AI Accelerator (courses, mentorship, templates) targeting AI automation agencies/founders. This audience IS Utkarsh's ICP.
  - **LinkedIn** — Inconsistent posting. Knows what to post (positioning is clear), needs execution discipline.
- **Goal**: Build authority through operational depth. Content = field notes from someone doing the work.
- **Content style**: Defined in positioning doc. Contrarian structure. Practitioner authority.

## 3. JTM Strategy
- **Status**: Active — figuring out
- **What**: Jobs-to-be-Made / Go-to-market strategy for getting meetings booked
- **Problem**: Not getting sales meetings despite having clear positioning and proof
- **Context**: Has 50+ implementations, enterprise clients (Loom, UpGrad), 2000+ reviews. The offer is strong. Distribution/conversion is the gap.

## 4. Internal Tools & Apps
- **Status**: Active — building
- **What**: Mapping own internal processes and building AI solutions around them
- **Purpose**: Not for selling — for own growth and operational efficiency
- **Approach**: Identify bottleneck processes → build AI solutions → use as proof of concept and content material

### 4a. n8n Workflow Reviewer
- **Status**: Built (2026-03-27), ready to deploy
- **What**: Production-grade web app for human-readable n8n workflow change review, selective merge, and push-to-production
- **Origin**: Pain point from Yosef's client Justin — workflow modifications broke production, no visibility into what changed
- **Core concept**: "Pull Requests for n8n workflows that non-technical clients can read and approve"
- **Stack**: Next.js 14 + shadcn/ui + jsondiffpatch + Supabase Auth + Prisma 6.x + Vercel
- **Key features**: Semantic diff engine, selective merge, client review links (token-based, no login), 3 push modes (duplicate/deactivate-push/direct), credential mapping, webhook URL preservation, Supabase Auth
- **Codebase**: `Projects/internal-tools/n8n-workflow-reviewer/` — 105 source files, 13 test files, 137 tests, 17 commits
- **PRD**: `Projects/internal-tools/n8n-workflow-reviewer-prd.md`
- **Plan**: `Projects/internal-tools/n8n-workflow-reviewer-plan.md`
- **Next step**: Deploy to Vercel + Supabase production (see `.env.example` for deployment steps)
- **Market context**: No dedicated SaaS exists for this. n8n built-in versioning locked behind 800 EUR/month. 230k+ users underserved.
- **Updated scope (2026-04-15)** — repositioning as "Reviewed Change History" (Option 4). Pivot driven by: (a) n8n shipped autosave + rollback Jan 2026 (free) killing naive VCS pitch, (b) clarified three-party role model (customer = client business / dev = agency team / user = outsourced contractor) with two-gate approval flow (user→dev→customer). Plan at `C:\Users\Utkarsh\.claude\plans\vast-tinkering-sundae.md` pending rewrite after user confirms permissions matrix for `user` role. Intended use: content asset (video + lead magnet + Vibelife proof page), not SaaS to scale.

## 5. Vibelife Website
- **Status**: Active — major repositioning underway
- **What**: Personal brand website for Utkarsh's Forward Deployed AI Partner positioning
- **Stack**: React 19 + Vite + TypeScript + Tailwind CSS 3 + GSAP + Framer Motion + Lenis smooth scroll
- **Location**: `Projects/vibelife-website/`
- **Design system**: BRAND-SYSTEM.md — Palantir depth + craftsman warmth. Void bg, gold/teal accents, Syne/DM Sans/DM Mono, neumorphic cards, grain texture, glass effects.
- **Current state (2026-04-02)**: 4-page site (/, /how-it-works, /work, /resources). Full copy rewrite pending — approved hero, structure, and positioning. Shifting from "domain expertise × AI" (generic operators) to "fulfillment partner for AI automation businesses" (specific ICP: $10-20K MRR agency owners).
- **Approved hero copy**:
  - Eyebrow: FOR AI AUTOMATION BUSINESSES
  - Headline: "We cleared 5 projects for one business in 21 days and they never touched fulfillment again"
  - Subtext: "If you're stuck building everything yourself we should probably talk"
- **Approved landing page structure**: Hero → Proof Bar → Problem → 3-Week Sandbox Offer → Before/After → Trust/Objections → CTA
- **Key files**: BRAND-SYSTEM.md, BRAND BIBLE.txt, app/tailwind.config.js, app/src/index.css
- **Next**: Implement full landing page rewrite, fix cursor, update Brand Bible with GTM playbook

## 6. GTM Strategy (90-Day Playbook)
- **Status**: Documented, not yet executing
- **What**: Go-to-market strategy for landing AI automation business partnerships
- **Target**: AI automation agency/business owners doing $10-20K MRR, drowning in fulfillment
- **Offer**: 3-week sandbox (clear backlog, prove quality) → ongoing partnership (20% rev-share)
- **Channels**: Cold email (primary), Skool communities (AI Automation Society Plus, Maker School, No-Code Architects), LinkedIn, YouTube
- **Content strategy**: YouTube as primary pillar (10-25 min videos, raw Remotion-powered), 1 video/week = 10-12 derivative pieces
- **Revenue target**: $10-20K MRR within 90 days (6-11 partners at ~$1,800/mo each)
- **Full playbook**: User shared comprehensive 90-day plan with weekly actions, metrics, tech stack, channel analysis, objection handling
- **Location**: Not yet saved as a vault file — needs to be saved from conversation

## 7. Paperclip Agent Orchestration
- **Status**: Active — installed, running, researching usage
- **What**: Open-source AI agent orchestration platform (company metaphor for managing agent teams)
- **Location**: `Tools/paperclip/` (cloned from github.com/paperclipai/paperclip)
- **Server**: http://127.0.0.1:3100 (pnpm dev)
- **Data**: `C:\Users\Utkarsh\.paperclip\instances\default\`
- **Purpose**: Operational backbone — orchestrate all Vibelife workstreams via AI agent teams
- **Planned agent structure**: CEO (Opus) → Delivery Engineer (Sonnet) + Content Researcher (Haiku) + Content Writer (Sonnet) + Lead Gen Agent (Haiku) + QA Agent (Sonnet)
- **Estimated monthly cost**: ~$345/mo in API fees (Paperclip itself is free MIT)
- **Research files**: `Research/paperclip-ai-platform-research.md`, `Reference/paperclip-ai-research.md`
- **Key insight**: "You are the board of directors. The agents are your employees." Not a workflow builder — it's the org chart for your AI workforce.
- **Next steps**: Create company in dashboard, hire CEO agent, define goals, run first heartbeat

## Key People
- **Yosef** — Primary client. Utkarsh builds automations for him and his clients.
- **Ben Van Sprundel** — Runs BenAI (benai.co). AI Accelerator community, mentorship program. His audience = Utkarsh's ICP. Utkarsh posts content in his community.
