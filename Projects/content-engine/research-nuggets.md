---
type: content-ideas
date: 2026-02-26
project: content-engine
status: active
tags: [nuggets, research, content-angles, linkedin, video]
source: [Research One.pdf, Research 2.pdf, vc-landscape-research]
---

# Research-Backed Content Nuggets

All nuggets extracted from two research papers (AGENTS.md evaluation + SkillsBench) and VC landscape research (a16z, YC, Sequoia, MIT, Bain Capital). Each nugget includes the raw research finding + dumbed-down audience-first content angles.

---

## Part 1: Content Angles From "Less > More" Pillar

### 1. Claude works better when you tell it less

Every single person in Audience A has been adding more and more to their prompts trying to get better output. You'd walk through what actually happens when you give AI too much (it gets confused, costs more, takes longer) and show what to keep vs. cut. The ETH Zurich data becomes one line: "researchers actually tested this — more instructions made AI 20% more expensive and less accurate." But the video/post is about THEIR Claude experience.

**Research backing:** AGENTS.md paper — context files reduced success rates while increasing cost by 20%+

---

### 2. Your Make.com workflow has too many steps

Every Audience A person who's built in Make has a spaghetti workflow. They added steps because something didn't work, so they patched it, then patched the patch. You'd show what a bloated workflow looks like vs. a clean one. The insight: the fix isn't adding — it's removing. This is the kind of content that makes someone DM you with a screenshot of their workflow.

**Research backing:** SkillsBench — 2-3 focused skills outperform comprehensive documentation. Comprehensive docs actually hurt performance by -2.9pp.

---

### 3. The 3 things your AI actually needs to know

Instead of "what I strip out" (about you), it's "what your AI needs" (about them). Most people give AI their entire company wiki. You'd show: it needs the routing logic (what goes where), the constraints (what NOT to do), and the one domain-specific thing it can't figure out on its own. Everything else is noise. Simple. Memorable. They can apply it immediately.

**Research backing:** SkillsBench — focused, surgical guidance outperforms exhaustive documentation every time. 2-3 modules optimal.

---

### 4. Why your AI gives different answers every time

This is a frustration every Audience A person has. They ask Claude the same question and get different results. Most people think the AI is broken. Your perspective: it's not the AI — it's that your setup gives it too much room to interpret. Focused context = consistent output. You don't need to say "architecture" — you just show it.

**Research backing:** AGENTS.md paper — agents given more instructions explore more broadly, use more reasoning tokens, but converge on answers less reliably.

---

### 5. Stop copying AI tutorials word for word

Every person in Audience A has followed a tutorial, copied it exactly, and gotten a different result. The reason: the tutorial was built for the creator's situation, not yours. Your perspective: the tutorial shows you the TOOL. It doesn't show you where the tool fits in YOUR process. That's the part that's different every time.

**Research backing:** SkillsBench — domain-specific guidance matters massively. Healthcare +51.9pp vs Software Engineering +4.5pp. Generic approaches fail in specific contexts.

---

## Part 2: Content Angles From "AI Needs Your Context" Pillar

### 6. Why the same AI tool works for one business and not another

Curiosity-driven. Both audiences have this experience. The answer isn't the tool — it's how it was set up for that specific business. Your perspective comes through in how you explain it: the setup is the business context, the variable is how your business actually runs. You'd show examples without using the word "architecture."

**Research backing:** SkillsBench — Skills efficacy varies 10x by domain. No universal solution.

---

### 7. Claude doesn't know how your team works

About their team, not about AI's limitations abstractly. The reason the AI outputs something the team can't use isn't that the AI is bad — it's that nobody told it about the team's actual workflow. You'd show what happens when you bridge that gap. Simple before/after.

**Research backing:** AGENTS.md — context files that describe codebase overviews don't help agents find relevant files faster. The AI needs process-specific knowledge, not general descriptions.

---

### 8. Your AI setup was built for the wrong person

Most AI setups are built by the founder/operator for themselves. Then they expect the team to use it. The team can't — because it was designed for how the founder thinks, not how the team works. Your perspective: this isn't a training problem, it's a setup problem.

**Research backing:** AGENTS.md — instructions followed perfectly, tasks still fail. The instructions pointed the system at the wrong target.

---

### 9. The part of AI nobody talks about

Vague enough to be curious, specific enough once they click. The "part" is what happens between "the AI works" and "the AI creates value." For Audience B: between "we delivered the automation" and "the client actually uses it." For Audience A: between "I built it" and "my business actually runs better." Your perspective is the lens. You don't say "adoption gap." You describe it in their experience.

**Research backing:** Both papers combined — having AI tools/context and getting actual results are two completely different things. The gap is measurable and consistent.

---

### 10. You don't need a better AI model. You need a better setup.

Directly challenges the default assumption. Everyone in Audience A thinks upgrading from Sonnet to Opus or getting GPT-5 will fix their problem. Your perspective: the model is rarely the bottleneck. The setup is. The SkillsBench data (Haiku + right process beat Opus without it) is one supporting line, not the topic.

**Research backing:** SkillsBench — Haiku 4.5 with curated Skills (27.7%) outperformed Opus 4.5 without Skills (22.0%). Smaller model + right process > bigger model + no process.

---

## Part 3: Research Findings That Go Beyond Positioning

These are NEW insights from the research that build on top of existing positioning — not repackaged.

### 11. The Dunning-Kruger of AI Tools

**Raw finding:** Developers using AI coding tools were 19% slower but believed they were 20% faster. A 39-percentage-point perception gap.

**What the audience is experiencing:** "I feel like I'm getting a lot done with Claude but when I look at my month... nothing really changed."

**Content angle A: "AI feels productive. But is it?"**
Everyone using AI tools feels like they're moving fast. You're generating stuff, automating stuff, building stuff. But the output of your month — the actual results — haven't changed. The feeling of productivity and actual productivity are two different things. Research just showed this is real: people using AI thought they were 20% faster. They were actually 19% slower.

**Content angle B: "The busiest I've ever been and the least I've ever shipped"**
You added AI to your workflow and now you're doing more tasks. More prompts, more automations, more experiments. But your core business output didn't move. That's not a you problem. There's a gap between AI activity and AI results that nobody talks about.

---

### 12. The 67% vs 22% Success Rate Gap

**Raw finding:** MIT NANDA report — companies working with a vendor partner succeed 67% of the time. Companies building internally: 22%. 3x difference.

**What the audience is experiencing:** "I've been trying to figure this out myself for two months now."

**Content angle A: "Why figuring out AI alone takes 3x longer"**
You watch the tutorial, follow the steps, and your result is different. So you watch another one. Then another. Two months later you're still tweaking. MIT tracked this: companies that brought in a partner got AI working 67% of the time. Companies that did it alone? 22%. It's not because you're bad at this. It's because your business is different from every tutorial.

**Content angle B: "The most expensive way to set up AI is doing it yourself"**
It sounds backwards. You'd think doing it yourself saves money. But every week you spend figuring it out is a week the tool isn't creating value. The research says you're 3x more likely to get it working with someone who's already done it for businesses like yours.

---

### 13. The Documentation Paradox

**Raw finding:** AGENTS.md paper — context files HURT performance when documentation already exists. But when ALL other docs were removed, context files helped by +2.7% and LLM-generated ones actually outperformed human-written ones.

**What the audience is experiencing:** "I don't even have my own process written down — I just do things."

**Content angle A: "Your AI doesn't know your process because YOU don't know your process"**
Most business owners can't explain how they do what they do. They just do it. Then they ask AI to help and get confused when the output doesn't match. The AI isn't guessing wrong — it's guessing blind. You haven't given it the thing it needs most: how your business actually runs, in plain steps.

**Content angle B: "Before you set up any AI tool, write down how you do your job"**
Not a fancy SOP. Not a 50-page manual. Just: what's step 1, what's step 2, what decision do you make at step 3 and why. That simple list is worth more to your AI than any prompt template you downloaded.

---

### 14. The Domain Gap Is Quantified — And It's Massive

**Raw finding:** SkillsBench — Healthcare saw +51.9pp improvement from human AI guidance. Manufacturing +41.9pp. Finance +15.1pp. Software Engineering? Only +4.5pp.

**What the audience is experiencing:** "All the AI tutorials are about tech companies. My business works differently."

**Content angle A: "AI tutorials don't work for your industry. Here's why."**
AI already knows how software works. It was trained on millions of code examples. But does it know how your logistics company routes deliveries? How your dental practice handles insurance claims? How your construction firm tracks material waste? The less AI knows about your industry from its training, the more it needs someone to explain YOUR world to it. Research shows the gap is massive — up to 52% difference.

**Content angle B: "The industries where AI needs the most help are the ones where it creates the most value"**
If you're NOT in tech, that's actually good news. The businesses where AI was least useful on its own saw the BIGGEST improvements when someone set it up properly. Your industry being "different" isn't a disadvantage — it's where the biggest gains are hiding.

---

### 15. When More Instructions Hurt

**Raw finding:** SkillsBench — 16 out of 84 tasks were made WORSE by adding structured guidance. Skills introduced conflicting guidance or unnecessary complexity for tasks the AI already handled well.

**What the audience is experiencing:** "I added more instructions to my prompt and somehow the output got worse."

**Content angle: "When to stop telling your AI what to do"**
There's a point where more instructions actually confuse your AI. It starts second-guessing. It tries to satisfy every rule you gave it and ends up satisfying none. Research found that nearly 20% of tasks got WORSE results when you added more guidance. The skill isn't knowing what to add. It's knowing when to stop.

---

### 16. 95% of GenAI Pilots Fail

**Raw finding:** MIT NANDA report — across 150 interviews, 350 employee surveys, 300 public deployments. 95% didn't deliver measurable ROI. Three failure modes: (1) "we need more AI" instead of "we need to solve this problem," (2) data pipelines aren't ready, (3) employees fear job loss.

**What the audience is experiencing:** "I bought ChatGPT Plus / Claude Pro / Make.com and... it's fine? I guess?"

**Content angle A: "You're not bad at AI. 95% of companies can't make it work either."**
MIT studied over 300 AI projects across real companies. 95% of them failed to deliver measurable results. Not because AI doesn't work. Because the way people set it up doesn't match how their business actually runs. You tried AI, it felt underwhelming, you assumed you were doing something wrong. You probably were — but so is almost everyone else.

**Content angle B: "The 5% who get AI working do one thing differently"**
They don't start with the tool. They start with the problem. Most people hear about AI, buy a tool, and then try to find something to use it on. The 5% who succeed pick a specific bottleneck in their business FIRST, then figure out which tool fits. That's it. That's the difference.

---

### 17. The "Taste" Economy

**Raw finding:** Sequoia Capital — as AI makes labor available at near-zero cost, "taste" becomes the new scarce resource. The differentiator is knowing WHAT to build and HOW it fits.

**What the audience is experiencing:** "Everyone has the same tools as me. What actually makes the difference now?"

**Content angle A: "Everyone has the same AI tools. So what actually matters now?"**
Claude, ChatGPT, Make, n8n — your competitors have access to all of it. The tools are getting cheaper every month. So what separates the business that gets results from the one that doesn't? It's not which tool you pick. It's knowing WHAT to build and WHERE it fits. The biggest investors in tech are saying the same thing: when everyone has the same tools, the person who knows what to do with them wins.

**Content angle B: "AI tools are getting cheaper. Here's what's getting more expensive."**
The cost of running AI dropped 83% in two years. By next year, the tool itself is basically free. What's going UP in value is the ability to look at a business, see where AI actually fits, and set it up so it sticks. That's not a tool skill. That's a thinking skill.

---

### 18. AI Went From Experiment to Core Infrastructure

**Raw finding:** a16z CIO survey — innovation budgets collapsed from 25% to just 7% of AI spend. AI is now core, not experimental. One CIO: "What I spent in 2023, I now spend in a week."

**What the audience is experiencing:** "We used to play with AI. Now we actually depend on it."

**Content angle A: "AI is no longer a side project in your business. Is it set up like one?"**
A year ago, AI was something you experimented with. Now your team uses it daily. Your clients expect it. Your competitors have it. But most businesses still have their AI set up the same way they set it up when they were just testing it. That prototype setup is now running your actual operations. Is it ready for that?

**Content angle B: "Your business runs on AI now. What happens when it breaks?"**
When AI was an experiment, it breaking meant nothing. Now it breaking means missed deadlines, angry clients, lost revenue. One CIO told a16z: "What I spent on AI in all of 2023, I now spend in a single week." The stakes changed. Did your setup change with it?

---

### 19. Automation Maintenance Exceeds Build Cost

**Raw finding:** Maintenance costs run 15-20% of initial investment annually. After 5 years, cumulative maintenance exceeds original build cost. RPA bot failure rate: 87%. A retailer with 200 automations faces 1,200+ UI changes/year that break bots.

**What the audience is experiencing:** "My automation broke again. I literally just fixed this last month."

**Content angle A: "Your automation will break. The question is whether it's designed to be fixed."**
Every automation breaks eventually. APIs update, data formats change, your process shifts. The ones that survive are designed with that in mind from day one. The ones that don't? You're rebuilding them every few months. And each rebuild costs more than the last because you're patching patches.

**Content angle B: "The automation that 'works' is costing you more than you think"**
It runs. It does the thing. But every month you spend 3 hours fixing it when something changes. Over a year, those hours add up to more than it cost to build. Research shows this is the pattern: maintenance costs 15-20% of the original build every single year. After 5 years, you've paid for it twice. Most people don't track this because each fix feels small.

---

### 20. The Referral Pipeline Already Exists (Audience B)

**Raw finding:** Nick Saraev refers overflow at 15% rev share. Liam Ottley's 35K graduates need fulfillment capacity. AI creators have distribution but not build capacity.

**What Audience B is experiencing:** "I'm selling more than I can build. I need help but I don't know who to trust with delivery."

**Content angle A: "You don't need more clients. You need someone to deliver for the ones you have."**
You figured out sales. Content is working. People are reaching out. But you're drowning in delivery. You tried hiring a freelancer and the work came back wrong. You tried doing it all yourself and burned out. The bottleneck in your business isn't leads. It's capacity to deliver at the quality that keeps clients.

**Content angle B: "The AI creators making real money have one thing in common: they don't build everything themselves"**
They have audience. They have distribution. They sell. But the actual building, deploying, and making sure it works? They have a partner for that. The top operators in this space already refer overflow work to trusted builders. That's not delegation. That's how the business scales.

---

## Quick Reference: Audience Mapping

| Nugget | Audience A (Business Owners) | Audience B (Agency Operators) | Both |
|--------|-----|-----|------|
| 1. Claude works better when you tell it less | Primary | | |
| 2. Make.com workflow has too many steps | Primary | | |
| 3. The 3 things your AI needs to know | Primary | Secondary | |
| 4. Why AI gives different answers | Primary | | |
| 5. Stop copying tutorials word for word | Primary | | |
| 6. Same tool works for one business not another | | | Both |
| 7. Claude doesn't know how your team works | Primary | Secondary | |
| 8. AI setup built for the wrong person | Primary | Secondary | |
| 9. The part of AI nobody talks about | | | Both |
| 10. You don't need a better model | Primary | Secondary | |
| 11. Dunning-Kruger of AI tools | | | Both |
| 12. 67% vs 22% success rate | | | Both |
| 13. Documentation paradox | Primary | | |
| 14. Domain gap | | | Both |
| 15. When more instructions hurt | Primary | | |
| 16. 95% of pilots fail | | | Both |
| 17. Taste economy | | | Both |
| 18. AI went from experiment to core | | | Both |
| 19. Maintenance exceeds build cost | Primary | Secondary | |
| 20. Referral pipeline exists | | Primary | |

---

## 1:1:1 Funnel Mapping

### Awareness (Who am I / What I do)
Best nuggets: 11, 12, 14, 16, 17 — These name patterns the audience feels but hasn't articulated. They position you as the person who sees what others miss.

### Nurture (Build trust)
Best nuggets: 1, 2, 3, 4, 5, 6, 7, 8, 13, 15, 18, 19 — These show operational depth and practical understanding. The audience thinks "this person gets it."

### Convert (Move to action)
Best nuggets: 9, 10, 12, 20 — These create the natural bridge. The gap does the work. The audience realizes they need help without being pitched.
