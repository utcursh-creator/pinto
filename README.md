# Personal Assistant OS

> Turn your Obsidian vault into an AI-powered second brain with Claude Code.

A complete personal assistant system where Claude reads your notes, remembers your preferences, manages your tasks, processes meeting transcripts, tracks your goals, and writes in your voice — all through natural conversation.

**Clone. Open in Obsidian. Run `/setup`. Start talking.**

---

## What It Does

| Feature | How It Works |
|---------|-------------|
| **Persistent Memory** | Claude remembers you across sessions — preferences, projects, learnings, work status |
| **Task Management** | Create, update, and track tasks via natural conversation (powered by TaskNotes) |
| **Meeting Intelligence** | Paste a transcript → auto-extract action items, decisions, summaries |
| **6 Output Styles** | Conversation, YouTube script, blog post, email, quick reply, meeting summary |
| **Goal Tracking** | 3-year vision → yearly goals → projects → monthly → weekly → daily tasks |
| **Daily Routines** | Morning check-in, evening reflection, weekly review — all via chat |
| **Session Memory** | Save and resume work sessions. Never lose context between conversations |
| **Teaching Loop** | Correct Claude once → it saves the rule → never makes that mistake again |

---

## Prerequisites

Before you start, make sure you have:

- [ ] **Obsidian** — Free download from [obsidian.md](https://obsidian.md)
- [ ] **Claude Code** — Install via `npm install -g @anthropic-ai/claude-code` (requires [Node.js](https://nodejs.org))
- [ ] **Anthropic API key** — Or Claude Max subscription for Claude Code

### Optional

- [ ] **Fireflies.ai** Business plan ($19/mo) — For automatic meeting transcript sync
- [ ] **Git** — For version control (recommended)

---

## Quick Start (5 Minutes)

### 1. Clone the repo

```bash
git clone https://github.com/adriiita/personal-assistant-os.git
cd personal-assistant-os
```

### 2. Open in Obsidian

1. Open Obsidian
2. Click **"Open folder as vault"**
3. Select the `personal-assistant-os` folder
4. When prompted, click **"Trust author and enable plugins"**

### 3. Install community plugins

The vault needs these plugins. Go to **Settings → Community Plugins → Browse**:

| Plugin | What It Does | Required? |
|--------|-------------|-----------|
| **TaskNotes** | Task management with calendar, kanban, time tracking | Yes |
| **Dataview** | Database-like queries on your notes | Yes |
| **Calendar** | Sidebar calendar for daily note navigation | Recommended |
| **Excalidraw** | Visual whiteboard and drawing | Optional |
| **Style Settings** | Theme customization | Optional |

> After installing, restart Obsidian to activate all plugins.

### 4. Launch Claude Code

```bash
claude
```

### 5. Personalize your vault

```
/setup
```

Claude will interview you about your work, preferences, and what you want to track — then build a personalized vault tailored to you.

---

## Commands

| Command | What It Does |
|---------|-------------|
| `/setup` | Interactive onboarding — personalizes your entire vault |
| `/resume` | Start a session — loads recent context, pending tasks, work status |
| `/compress` | Save session — creates searchable session log before you close |
| `/preserve` | Save permanent learnings — durable knowledge with auto-archiving |
| `/daily-review` | Morning check-in, evening reflection, or weekly review |

### Daily Workflow

```
Morning:   /resume → /daily-review
           Loads your context, plans your day

During:    Just talk naturally
           "Add a task: finish proposal by Friday"
           "What did we discuss in last week's standup?"
           "Write a YouTube script about personal branding"

Evening:   /compress
           Saves everything for next session
```

---

## Architecture

### What You See in Obsidian

```
Inbox/          → Quick capture. Drop anything here
Thinking/       → Your ideas, synthesis, thinking patterns
Projects/       → Active project folders
Meetings/       → Meeting transcripts and summaries
  ├── team-standups/
  ├── client-calls/
  ├── one-on-ones/
  └── general/
Daily/          → Daily journals and check-ins
Reference/      → External knowledge, tools, guides
Archive/        → Completed or inactive content
Goals/          → Vision, yearly goals, monthly goals
TaskNotes/      → Task management (managed by TaskNotes plugin)
```

### What Powers It (Hidden in `.claude/`)

```
.claude/
├── commands/         → /setup, /resume, /compress, /preserve, /daily-review
├── context/
│   ├── memory/       → learnings, preferences, projects, work status
│   ├── projects/     → Deep context per project
│   └── session-logs/ → Searchable session history
├── hooks/            → Auto-inject context + force memory updates
├── output-styles/    → 6 writing styles
├── settings.json     → Hooks configuration
└── skills/           → Task management, meetings, Fireflies, daily review
```

### How the Layers Work

```
┌─────────────────────────────────────────────┐
│  CLAUDE.md (Root Brain)                     │
│  Routes to subsystems based on your request │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┼──────────────┐
    ▼          ▼              ▼
┌────────┐ ┌──────────┐ ┌──────────┐
│ Memory │ │ Output   │ │ Skills   │
│ System │ │ Styles   │ │          │
└────────┘ └──────────┘ └──────────┘
    │          │              │
    ▼          ▼              ▼
 Knows you   Writes in     Takes action
 across      your voice    (tasks, meetings,
 sessions                   reviews, etc.)
```

---

## Task Management (TaskNotes)

TaskNotes is the built-in task system. Claude creates and manages tasks via API — you just talk naturally.

### Creating Tasks

```
"Add a task: review the proposal, high priority, due Friday"
"Create a task to prepare for the client meeting tomorrow"
"I need to write the blog post draft by next week"
```

### Managing Tasks

```
"What tasks are overdue?"
"Move 'review proposal' to in-progress"
"Mark the blog post draft as done"
"Show me my tasks for this week"
```

### Built-in Views

TaskNotes comes with 6 views you can open in Obsidian:

| View | What It Shows |
|------|--------------|
| **Task List** | All tasks with 6 tabs (All, Not Blocked, Today, Overdue, This Week, Unscheduled) |
| **Kanban Board** | Visual columns by status (Open → In Progress → Done) |
| **Calendar** | Weekly time grid with tasks on time slots |
| **Mini Calendar** | Month overview with dots for task dates |
| **Agenda** | Flat list of upcoming 7 days |
| **Relationships** | Task dependencies, subtasks, blocking chains |

### Features

- Priorities (none, low, normal, high) with color coding
- Due dates and scheduled dates
- Task dependencies (blocked-by / blocking)
- Time tracking and Pomodoro timer
- Urgency scoring (priority + deadline proximity)
- Tags, contexts, and project grouping

---

## Meeting Intelligence

### Option 1: Manual Paste (Free)

1. Copy your meeting transcript from Zoom, Google Meet, Fireflies, Otter, etc.
2. Paste it into the chat
3. Claude extracts decisions, action items, and creates a structured summary
4. Offers to create tasks from action items

### Option 2: Fireflies MCP (Business Plan — $19/mo)

1. Connect Fireflies via MCP server
2. Say "sync my meetings"
3. Claude pulls and processes transcripts automatically

Meeting notes are saved to `Meetings/` in the right subfolder (team-standups, client-calls, one-on-ones, general).

---

## Output Styles

Tell Claude how to write, and it switches style:

| Style | Trigger | Example Output |
|-------|---------|---------------|
| **Conversation** | Default | Natural, concise chat |
| **YouTube Script** | "Write a YouTube script about..." | Hook → Setup → Content → CTA with visual cues |
| **Blog Post** | "Write a blog post about..." | Headline → Intro → Sections → Takeaway |
| **Email** | "Draft an email to..." | Subject → Greeting → Body → CTA → Sign-off |
| **Quick Reply** | "Reply to this DM..." | 1-3 sentences, casual, matches platform |
| **Meeting Summary** | Paste a transcript | Decisions → Action Items → Summary → Follow-up |

Each style is a markdown file in `.claude/output-styles/`. Add your own or customize existing ones.

---

## Goal Tracking

The goal cascade connects your long-term vision to daily actions:

```
3-Year Vision → Yearly Goals → Projects → Monthly Goals → Weekly Review → Daily Tasks
```

- Goals live in `Goals/` (vision.md, yearly-goals.md, monthly-goals.md)
- Projects in `Projects/` link to goals
- Tasks link to projects via TaskNotes
- Weekly reviews flag goals that have no active project

---

## Memory System

### How Claude Remembers

Three mechanisms work together:

1. **Hooks** (automatic) — Every conversation turn, hooks inject your memory and remind Claude to update it
2. **Session Logs** (`/compress`) — Structured summaries of past work sessions with Quick Reference sections for fast AI scanning
3. **Permanent Memory** (`/preserve`) — Durable knowledge that persists indefinitely with auto-archiving

### Memory Files

| File | What It Stores |
|------|---------------|
| `learnings.md` | Insights, patterns, things that worked or failed |
| `user_preferences.md` | Communication style, work habits, tool preferences |
| `user_projects.md` | Active projects, deadlines, key details |
| `work_status.md` | What happened this session, pending items, next steps |

### The Teaching Loop

When you correct Claude:
1. It applies the correction immediately
2. Asks: "Should I save this as a permanent rule?"
3. If yes → adds the rule to CLAUDE.md
4. Never makes that mistake again

Over time, the system learns exactly how you like things done.

---

## Privacy & Safety

**Important**: Claude Code sends your vault content to Anthropic's servers for processing.

### Protect Yourself

- **`.claudeignore`** — Already included. Add paths to folders Claude should never read
- **Keep secrets outside** — Passwords, API keys, credentials should not be in the vault
- **Version control** — Use `git init` and commit regularly
- **Review changes** — Check what Claude creates before committing

### What's Included

```
.claudeignore     → Excludes sensitive folders from Claude's access
.gitignore        → Ready for git, excludes OS files and plugin binaries
```

---

## For Claude Co-Work Users

This system works in both Claude Code and Claude Co-Work, with different capabilities:

| Feature | Claude Code | Co-Work |
|---------|-------------|---------|
| Read/write files | Yes | Yes |
| CLAUDE.md instructions | Yes | Yes |
| Memory hooks (auto-update) | Yes | No |
| Slash commands | Yes | No |
| TaskNotes API | Yes | No |
| Skills | Yes | No |

**Co-Work workaround**: Manually tell Claude to "check my memory files" at the start and "update my work status" at the end of each session.

---

## Customization

### Add Your Own Output Style

Create a new `.md` file in `.claude/output-styles/` following the pattern:

```markdown
# Style Name

## Identity
Who are you when writing in this style?

## Tone
What's the emotional register?

## Format
What's the structural template?

## Rules
What must you always/never do?
```

### Add a New Skill

Create a folder in `.claude/skills/your-skill/SKILL.md`:

```markdown
---
name: your-skill
description: What it does and when to use it
---

# Your Skill

USE WHEN the user...

## How It Works
[Instructions for Claude]
```

### Modify Folder Structure

The `/setup` command builds folders based on your interview answers. You can always:
- Add new folders manually
- Create `_guide.md` files in any folder to teach Claude what goes there
- Update the vault structure section in `CLAUDE.md`

---

## Acknowledgments

Inspired by and built on ideas from:
- [Claude Code Obsidian Starter](https://github.com/ArtemXTech/claude-code-obsidian-starter) by Artem Zhutov
- The "L" personal assistant system by Daniel Miessler
- Heinrich's vault philosophy and proactive vault concepts
- The Claude Code + Obsidian community

---

## License

MIT — Use it, modify it, make it yours.
# ai
