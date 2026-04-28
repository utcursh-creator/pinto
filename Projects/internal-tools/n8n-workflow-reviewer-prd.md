---
type: prd
date: 2026-03-26
project: internal-tools
status: draft
tags: [n8n, version-control, workflow-review, saas, production]
---

# n8n Workflow Reviewer — Product Requirements Document

## 1. Product Overview

### Problem
When an agency developer modifies a client's n8n workflow, the client has no way to see what changed, verify the changes are correct, or safely approve them before they go live. This leads to broken workflows, lost trust, and a manual workaround of duplicating → modifying → testing → replacing.

### Solution
A production-grade web application that provides human-readable workflow change review, selective merge, and safe push-to-production for n8n workflows. Non-technical clients can review, comment on, and approve changes through a shareable link — without ever touching JSON or n8n directly.

### Core Value Proposition
**Pull Requests for n8n workflows that non-technical clients can read and approve.**

### Origin
This solution was identified from a real pain point with client Justin (via Yosef), where workflow modifications broke production because there was no visibility into what changed. The manual workaround (duplicate → modify → test → replace) works but doesn't scale and provides no audit trail.

---

## 2. User Personas

### Persona 1: Agency Developer (Primary — e.g., Utkarsh)
- Builds and modifies n8n workflows for clients
- Needs to show clients what changed in a clear way
- Needs to push approved changes back to client's n8n instance safely
- Technical user — comfortable with JSON, APIs, and n8n internals

### Persona 2: Client Reviewer (e.g., Justin)
- Owns the n8n instance where workflows run in production
- Non-technical — does NOT read JSON or understand n8n internals
- Needs to see changes in plain English
- Needs to approve or request modifications before anything goes live
- Accesses the tool via a shareable link — no account creation required

---

## 3. Feature Specification

### 3.1 Instance Connection Management

**Description:** Securely connect to one or more n8n instances via API key.

**Requirements:**
- Store n8n instance URL + API key (encrypted at rest with AES-256)
- Validate connection on setup (test API call to `GET /api/v1/workflows`)
- Support multiple instances (e.g., one per client)
- Display connection status (connected/disconnected/error)
- All n8n API calls proxied through backend — API keys never exposed to frontend

**Data model:**
```
Instance {
  id: uuid
  name: string              // "Justin's n8n"
  url: string               // "https://cloud.n8n.io/xyz"
  api_key: string           // encrypted
  user_id: uuid             // owner
  status: enum              // connected | disconnected | error
  last_verified_at: datetime
  created_at: datetime
}
```

### 3.2 Workflow Comparison (Two Entry Points)

**Entry Point A — JSON Upload:**
- Drag-and-drop upload of two JSON files (before + after)
- Validate both files are valid n8n workflow JSON (check for `nodes`, `connections`, `name` fields)
- No instance connection required — works standalone

**Entry Point B — Connected Instance + Upload:**
- Select a workflow from a connected instance (fetched via `GET /api/v1/workflows`)
- Current live version auto-fetched as "before" (real-time, no stale exports)
- Upload modified version as "after"
- This solves the stale-state problem at the input level

**Requirements:**
- File size limit: 10MB per JSON (covers even very large workflows)
- Validation error messages: "Invalid n8n workflow JSON — missing 'nodes' array"
- Store both JSONs for history/audit

### 3.3 Semantic Diff Engine (Core IP)

**Description:** Parses two n8n workflow JSONs and produces a human-readable, categorized changelog.

**Change Categories:**

| Category | Icon | Color | Description |
|----------|------|-------|-------------|
| Added Nodes | + | Green | New nodes in the workflow |
| Removed Nodes | - | Red | Nodes deleted from the workflow |
| Modified Nodes | ~ | Amber | Parameter, credential, or config changes on existing nodes |
| Connection Changes | 🔗 | Blue | New, removed, or rewired connections between nodes |
| Workflow Settings | ⚙ | Gray | Changes to workflow-level settings (name, active status, etc.) |
| Security Flags | ⚠ | Orange | Credential changes, webhook URL changes, sensitive parameter changes |

**Noise Filtering (suppressed from output):**
- `position` changes (node x,y coordinates on canvas) — visual only, no functional impact
- `id` rotations (internal UUIDs that change on export/import)
- `pinData` changes (test data pinned in the editor)
- `meta` changes (editor metadata)
- `versionId` changes (n8n internal versioning)
- Whitespace/formatting differences in string parameters

**Semantic Translation Rules:**

| Raw JSON change | Semantic output |
|-----------------|-----------------|
| New object in `nodes[]` | "Added node: **{name}** (type: {humanReadableType})" |
| Removed object from `nodes[]` | "Removed node: **{name}**" |
| Changed `nodes[i].parameters.X` | "**{nodeName}**: {parameterName} changed from `{old}` to `{new}`" |
| Changed `nodes[i].disabled` | "**{nodeName}**: {enabled → disabled / disabled → enabled}" |
| New entry in `connections` | "Connected: **{sourceNode}** → **{targetNode}**" |
| Removed entry from `connections` | "Disconnected: **{sourceNode}** → **{targetNode}**" |
| Changed `connections` routing | "Rewired: **{sourceNode}** now connects to **{newTarget}** (was **{oldTarget}**)" |
| Changed `nodes[i].credentials` | "⚠ Security: Credential changed on **{nodeName}** — was `{oldCred}`, now `{newCred}`" |
| Changed `active` | "Workflow **activated** / **deactivated**" |
| Changed `name` | "Workflow renamed: `{old}` → `{new}`" |
| Changed `settings.X` | "Setting changed: {settingName} from `{old}` to `{new}`" |

**Node Type Mapping (human-readable names):**

The engine must map n8n internal node type identifiers to human-readable names:

| Internal type | Display name |
|---------------|-------------|
| `n8n-nodes-base.httpRequest` | HTTP Request |
| `n8n-nodes-base.if` | IF / Router |
| `n8n-nodes-base.set` | Set Values |
| `n8n-nodes-base.code` | Code (JavaScript/Python) |
| `n8n-nodes-base.webhook` | Webhook Trigger |
| `n8n-nodes-base.emailSend` | Send Email |
| `n8n-nodes-base.postgres` | PostgreSQL |
| `n8n-nodes-base.slack` | Slack |
| ... | (extensible registry — parse type string for fallback) |

**Fallback for unknown types:** Parse the type string — `n8n-nodes-base.googleSheets` → "Google Sheets"

**Deep Parameter Path Humanization:**

n8n parameters are deeply nested. Raw paths like `parameters.headerParameters.parameters[0].value` are unreadable. The semantic layer must humanize these paths per node type.

| Raw parameter path | Humanized display |
|-------------------|-------------------|
| `parameters.headerParameters.parameters[N].value` | "Header '{name}' value" |
| `parameters.bodyParameters.parameters[N].value` | "Body param '{name}' value" |
| `parameters.queryParameters.parameters[N].value` | "Query param '{name}' value" |
| `parameters.authentication.*` | "Authentication: {field}" |
| `parameters.options.redirect.follow` | "Setting: Follow redirects" |
| `parameters.jsCode` or `parameters.code` | (Code node — render as code diff, not text change) |
| `parameters.conditions.conditions[N].*` | "Condition {N+1}: {field}" |
| `parameters.url` | "URL" |
| `parameters.method` | "HTTP Method" |
| `parameters.resource` | "Resource" |
| `parameters.operation` | "Operation" |

**Fallback for unregistered parameter paths:** Show the last 2 segments of the path in Title Case. `parameters.options.batching.batchSize` → "Batching: Batch Size"

**Code Node Special Handling:**

For nodes where `type` contains `code`, `function`, or `Code`:
- Do NOT show parameter text diff
- Instead, extract the code content from `parameters.jsCode`, `parameters.code`, or `parameters.pythonCode`
- Render a proper side-by-side code diff using react-diff-viewer with syntax highlighting
- Show language label: "JavaScript" or "Python"

**Sticky Note / Documentation Node Handling:**

Sticky Notes (`n8n-nodes-base.stickyNote`) are documentation, not functional nodes:
- Categorize separately as "Documentation Changes" (not mixed with functional changes)
- Display with muted styling — below functional changes
- Also include: changes to any node's `notes` field (the small description text on nodes)

**Dependency Grouping:**

Related changes are bundled as atomic groups:
- When a node is ADDED → its connections (inbound + outbound) are grouped with it
- When a node is REMOVED → its disconnections are grouped with it
- Group description: "These changes are linked — accepting the node also accepts its connections"
- Each group can be accepted/rejected as a unit

**Technical Implementation:**

```
Input:  before.json, after.json
        ↓
Step 1: jsondiffpatch.diff(before, after)  →  raw structural diff
        ↓
Step 2: Noise filter  →  remove position, pinData, meta, versionId changes
        ↓
Step 3: Semantic mapper  →  translate each change to human-readable format
        ↓
Step 4: Dependency grouper  →  bundle related changes
        ↓
Step 5: Security flagger  →  mark credential/webhook changes
        ↓
Output: Structured changelog with categories, groups, and descriptions
```

### 3.4 Review Interface

**For Agency Developer:**
- Full changelog with checkboxes on each change/group
- "Accept All" / "Reject All" quick actions
- "See details" expander on each change — shows the actual JSON diff for power users
- For **Code nodes** specifically: "See details" renders a proper side-by-side code diff (react-diff-viewer), not raw JSON
- Summary bar: "X nodes added, Y modified, Z connections changed"
- "Share with Client" button → generates shareable review link
- Comparison description field (like a commit message): "Added invoice validation step" — entered at creation, shown in history
- "Download Merged JSON" button — available at all times after merge, critical for upload-only flow (no connected instance)

**Change Categories in Display Order:**
1. **Security Flags** (top — always visible, orange) — credential changes, webhook URL changes
2. **Added Nodes** (green) — new nodes + their connections (grouped)
3. **Removed Nodes** (red) — deleted nodes + their disconnections (grouped)
4. **Modified Nodes** (amber) — parameter/config changes on existing nodes
5. **Connection Changes** (blue) — rewired or standalone connection changes
6. **Workflow Settings** (gray) — name, active status, global settings
7. **Documentation Changes** (muted/subtle) — Sticky Note content, node description fields, workflow-level notes

**For Client Reviewer (via shareable link):**
- Same changelog, but READ-ONLY (no checkboxes)
- **Name entry on first visit:** "You're reviewing changes to {workflow}. Your name:" → stored in cookie/localStorage for the session
- Comment thread per change — client can ask questions, developer can respond
- Global comment thread for overall feedback
- "Approve All" button — signals approval to the developer
- "Request Changes" button — requires at least one comment explaining what to change
- No login required — accessed via unique token URL
- Token expiry: 30 days (configurable)
- **Mobile-responsive from day one** — this screen is the client-facing interface. Clients may open review links on mobile (e.g., from WhatsApp). Changelog cards stack vertically, comment threads collapse, approve/reject buttons are thumb-friendly.

**Empty State — No Changes Detected:**
If the before and after JSONs are functionally identical (after noise filtering), show:
"No functional changes detected. The workflows are identical. Any differences are cosmetic (node positioning, metadata)."
With option to: "Show cosmetic changes anyway" (for debugging).

**Feedback Loop — "Request Changes" Flow:**
When a client clicks "Request Changes":
1. Comparison status → `changes_requested`
2. Developer sees the status + client's comments on their dashboard
3. Developer modifies the workflow, then uploads a new "after" JSON on the SAME comparison
4. System creates a **new revision** — re-diffs against the original "before"
5. Existing comments are preserved, new changes are highlighted as "New in revision 2"
6. Client's review link auto-shows the latest revision
7. Previous revisions are accessible via "Revision history" dropdown

**Data model:**
```
Comparison {
  id: uuid
  user_id: uuid
  instance_id: uuid (nullable — null if JSON upload)
  workflow_id: string (nullable — the n8n workflow ID if connected)
  workflow_name: string
  description: text            // developer's description — like a commit message
  before_json: jsonb
  status: enum                 // draft | pending_review | approved | changes_requested | merged | pushed
  review_token: string         // unique token for client link
  review_token_expires_at: datetime
  created_at: datetime
  updated_at: datetime
}

ComparisonRevision {
  id: uuid
  comparison_id: uuid
  revision_number: integer     // 1, 2, 3...
  after_json: jsonb
  diff_result: jsonb           // raw jsondiffpatch output for this revision
  semantic_changelog: jsonb    // human-readable changes for this revision
  merged_json: jsonb (nullable) // result after selective merge (null until merged)
  created_at: datetime
}

Comment {
  id: uuid
  comparison_id: uuid
  revision_number: integer     // which revision this comment was made on
  change_group_id: string (nullable — null for global comments)
  author_name: string          // "Utkarsh" or "Justin"
  author_role: enum            // developer | client
  content: text
  created_at: datetime
}

ChangeSelection {
  id: uuid
  comparison_id: uuid
  revision_id: uuid
  change_group_id: string
  accepted: boolean
  selected_by: uuid
  selected_at: datetime
}
```

### 3.5 Selective Merge Engine

**Description:** Takes the "before" JSON, the full diff, and the user's selections — produces a merged JSON containing only the accepted changes.

**Implementation:**

```
Input:  before.json, fullDiff (from jsondiffpatch), selections (accepted change IDs)
        ↓
Step 1: Clone the fullDiff object
        ↓
Step 2: Walk the diff tree — remove any changes NOT in the accepted selections
        (this is the "diff pruner")
        ↓
Step 3: jsondiffpatch.patch(before, prunedDiff)  →  merged JSON
        ↓
Step 4: Validate merged JSON against n8n schema
        (must have valid nodes[], connections{}, required fields)
        ↓
Output: merged.json — ready to push
```

**Edge Cases:**
- If ALL changes accepted → merged = after.json (no pruning needed)
- If NO changes accepted → merged = before.json (no patch needed)
- If a grouped change is partially accepted → warn user, force accept/reject entire group
- If removing a connection but keeping the node → valid (orphan nodes are allowed in n8n)
- If keeping a connection but removing its target node → INVALID → block and warn

**Validation after merge:**
1. All connections reference nodes that exist in the merged `nodes[]` array
2. All node names in `connections` match actual node names
3. Required fields present (`nodes`, `connections`, `name`)
4. JSON is parseable and under size limit
5. **Expression reference validation:** Scan all parameter string values for `$node["..."]` patterns. Verify each referenced node name exists in the merged `nodes[]`. If a referenced node was removed or renamed → warn: "Expression in **{nodeName}** references **{missingNode}** which doesn't exist in the merged workflow. This will cause a runtime error."
6. **Sub-workflow reference validation:** Detect `executeWorkflow` nodes. Warn if referenced workflow IDs may not exist on the target instance.

### 3.6 Push to n8n

**Description:** Pushes the merged workflow JSON to the target n8n instance via API.

**Pre-Push Safety Checks:**

| Check | Action if failed |
|-------|-----------------|
| Instance connection alive | "Cannot connect to {instance}. Check API key and URL." |
| Target workflow still exists | "Workflow '{name}' no longer exists on {instance}." |
| Stale state detection | Fetch current live workflow, compare against stored "before". If different: "⚠ The live workflow has been modified since your baseline. Changes may conflict. Re-export recommended." |
| Active workflow warning | "This workflow is currently ACTIVE (running in production)." |

**Push Modes:**

| Mode | Description | When to use |
|------|-------------|-------------|
| **Push as duplicate** (recommended default) | Creates a NEW workflow with the merged JSON. Name: "{original} — Review Copy". Client tests it, then manually swaps. | Safest. Mirrors the workaround from the transcript but automated. |
| **Deactivate → Push → Prompt** | Deactivates the live workflow, pushes changes in-place, prompts user to test and reactivate. | When client trusts the changes and wants them in the original workflow. |
| **Direct push** | Overwrites the live workflow without deactivating. | Only for non-production or inactive workflows. Show confirmation dialog. |

**Push Implementation:**

```
Mode: Push as duplicate
  POST /api/v1/workflows
  Body: merged JSON with name = "{original} — Review Copy", active = false

Mode: Deactivate → Push
  POST /api/v1/workflows/:id/deactivate
  PATCH /api/v1/workflows/:id  Body: merged JSON
  // Do NOT auto-reactivate — let user test first

Mode: Direct push
  PATCH /api/v1/workflows/:id  Body: merged JSON
```

**Credential Mapping (on push):**

If the merged JSON contains credential references, and those credentials don't exist on the target instance:
1. Fetch available credentials via `GET /api/v1/credentials`
2. Show mapping UI: "Credential '{name}' (type: {type}) → Select matching credential on target instance"
3. Replace credential IDs in the merged JSON before pushing
4. If no matching credential found → warn: "Missing credential. Push will succeed but the node won't authenticate."
5. Detect NEW credential requirements (nodes added that need credentials not present in "before") — warn separately: "New node **{name}** requires a **{credentialType}** credential. Select or create one on the target instance."

**Webhook URL Preservation (on push):**

Webhook nodes have instance-specific paths. If the developer worked on a different instance:
1. Detect webhook nodes in the merged JSON
2. Compare webhook paths against the target instance's current webhook configuration
3. If paths differ → warn: "Webhook node **{name}** has path `{devPath}`. The target instance currently uses `{prodPath}`. Which should be used?"
4. Option to preserve target instance's webhook path (recommended default) or use the new path

**Download Merged JSON (for upload-only flow):**

When no instance is connected (Entry Point A — JSON upload only):
- After selective merge, show "Download Merged JSON" as the primary action (instead of "Push")
- Download filename: `{workflowName}-merged-{date}.json`
- The user can then manually import this into n8n via the n8n UI

**Post-Push:**
- Record the push in comparison history (status: pushed)
- Show success screen with link to the workflow on the n8n instance
- If pushed as duplicate: show both the original and duplicate workflow links

### 3.7 Comparison History & Audit Trail

**Description:** Complete record of all comparisons, reviews, and pushes.

**Requirements:**
- List all comparisons with status, date, workflow name, instance
- Filter by: instance, status, date range
- Each comparison stores: before JSON, after JSON, diff, selections, comments, push result
- Searchable by workflow name
- Exportable (for compliance / client reporting)

---

## 4. Technical Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        FRONTEND                              │
│                   Next.js 14 (App Router)                    │
│                      + shadcn/ui                             │
│                 + react-diff-viewer-continued                │
│                     + react-dropzone                         │
├─────────────────────────────────────────────────────────────┤
│                     NEXT.JS API ROUTES                       │
│               /api/comparisons                               │
│               /api/instances                                 │
│               /api/push                                      │
│               /api/review/[token]                            │
├─────────────────────────────────────────────────────────────┤
│                      CORE ENGINE                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ jsondiffpatch │  │  Semantic    │  │   Merge      │      │
│  │  (diff/patch) │  │  Translator  │  │   Engine     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Noise      │  │  Dependency  │  │   n8n API    │      │
│  │   Filter     │  │  Grouper     │  │   Client     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
├─────────────────────────────────────────────────────────────┤
│                      STORAGE                                 │
│              Supabase (PostgreSQL + Auth + Storage)           │
│                                                              │
│  Tables: instances, comparisons, comments, change_selections │
│  Storage: uploaded JSON files                                │
│  Auth: admin users (Supabase Auth), clients (token-based)    │
├─────────────────────────────────────────────────────────────┤
│                     EXTERNAL                                 │
│           Client's n8n instance (via REST API)               │
│                 (proxied through backend)                     │
└─────────────────────────────────────────────────────────────┘
```

### Technology Stack

| Layer | Technology | Version | License | Purpose |
|-------|-----------|---------|---------|---------|
| Framework | Next.js | 14.x (App Router) | MIT | Frontend + API routes |
| UI Components | shadcn/ui | Latest | MIT | Production-grade UI components |
| Diff Engine | jsondiffpatch | 0.6.x | MIT | JSON structural diffing + patching |
| Visual Diff | react-diff-viewer-continued | 4.x | MIT | "See details" code diff display |
| File Upload | react-dropzone | 14.x | MIT | Drag-and-drop JSON upload |
| Database | Supabase (PostgreSQL) | Latest | Apache 2.0 | Relational storage + auth |
| ORM | Prisma | 5.x | Apache 2.0 | Type-safe database access |
| State | Zustand | 4.x | MIT | Lightweight client-side state |
| Encryption | Node.js crypto (aes-256-gcm) | Built-in | — | API key encryption at rest |
| Deployment | Vercel | — | — | Hosting, HTTPS, edge functions |
| TypeScript | TypeScript | 5.x | Apache 2.0 | Type safety throughout |

### Security Architecture

1. **API Key Storage:** n8n API keys encrypted with AES-256-GCM using a server-side encryption key (environment variable). Never sent to the frontend.
2. **n8n API Proxy:** All calls to client n8n instances are proxied through Next.js API routes. The frontend sends `instanceId`, the backend resolves the encrypted API key and makes the call.
3. **Client Review Links:** Token-based (UUID v4). No authentication required for clients. Tokens expire after 30 days. Tokens are single-comparison scoped — cannot be used to access other comparisons.
4. **CSRF Protection:** Next.js built-in CSRF protection on API routes.
5. **Input Validation:** All uploaded JSON files validated against n8n schema before processing. Size limit: 10MB.
6. **No Credential Secrets:** n8n workflow JSON contains credential IDs and names but NOT actual secrets. Safe to store and display.

---

## 5. Database Schema

```sql
-- Connected n8n instances
CREATE TABLE instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL,
  url TEXT NOT NULL,
  encrypted_api_key TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'connected',  -- connected | disconnected | error
  last_verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Workflow comparisons (parent — holds the baseline and metadata)
CREATE TABLE comparisons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  instance_id UUID REFERENCES instances(id),
  workflow_id TEXT,                  -- n8n workflow ID (if connected)
  workflow_name TEXT NOT NULL,
  description TEXT,                 -- developer's commit-message-style description
  before_json JSONB NOT NULL,       -- baseline (stays constant across revisions)
  status TEXT NOT NULL DEFAULT 'draft',
    -- draft | pending_review | approved | changes_requested | merged | pushed
  review_token TEXT UNIQUE,
  review_token_expires_at TIMESTAMPTZ,
  push_mode TEXT,                   -- duplicate | deactivate_push | direct
  push_result JSONB,               -- API response from push
  pushed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Comparison revisions (each new "after" upload creates a revision)
CREATE TABLE comparison_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comparison_id UUID NOT NULL REFERENCES comparisons(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL DEFAULT 1,
  after_json JSONB NOT NULL,
  diff_result JSONB NOT NULL,       -- raw jsondiffpatch output
  semantic_changelog JSONB NOT NULL, -- human-readable changes
  merged_json JSONB,                -- result after selective merge (null until merged)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(comparison_id, revision_number)
);

-- Comments on comparisons (persist across revisions, tagged to revision)
CREATE TABLE comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  comparison_id UUID NOT NULL REFERENCES comparisons(id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL DEFAULT 1,
  change_group_id TEXT,             -- null = global comment
  author_name TEXT NOT NULL,
  author_role TEXT NOT NULL,        -- developer | client
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Change accept/reject selections (per revision)
CREATE TABLE change_selections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  revision_id UUID NOT NULL REFERENCES comparison_revisions(id) ON DELETE CASCADE,
  change_group_id TEXT NOT NULL,
  accepted BOOLEAN NOT NULL DEFAULT true,
  selected_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_comparisons_user ON comparisons(user_id);
CREATE INDEX idx_comparisons_instance ON comparisons(instance_id);
CREATE INDEX idx_comparisons_status ON comparisons(status);
CREATE INDEX idx_comparisons_token ON comparisons(review_token);
CREATE INDEX idx_revisions_comparison ON comparison_revisions(comparison_id);
CREATE INDEX idx_comments_comparison ON comments(comparison_id);
CREATE INDEX idx_selections_revision ON change_selections(revision_id);
```

---

## 6. API Design (Next.js API Routes)

### Instance Management
```
POST   /api/instances              — Connect a new n8n instance
GET    /api/instances              — List connected instances
GET    /api/instances/:id          — Get instance details
PATCH  /api/instances/:id          — Update instance (name, API key)
DELETE /api/instances/:id          — Remove instance
POST   /api/instances/:id/verify   — Test connection to n8n instance
GET    /api/instances/:id/workflows — List workflows on the instance (proxied)
```

### Comparisons
```
POST   /api/comparisons            — Create new comparison (upload JSONs or select workflow)
GET    /api/comparisons            — List all comparisons (with filters)
GET    /api/comparisons/:id        — Get comparison details + latest revision changelog
PATCH  /api/comparisons/:id        — Update comparison (description, status)
DELETE /api/comparisons/:id        — Delete comparison

POST   /api/comparisons/:id/share  — Generate client review link (token)
POST   /api/comparisons/:id/push   — Push merged result to n8n instance
```

### Revisions
```
POST   /api/comparisons/:id/revisions      — Upload new "after" JSON (creates new revision)
GET    /api/comparisons/:id/revisions       — List all revisions for a comparison
GET    /api/comparisons/:id/revisions/:rev  — Get specific revision's changelog
POST   /api/comparisons/:id/revisions/:rev/merge — Execute selective merge on a revision
GET    /api/comparisons/:id/revisions/:rev/download — Download merged JSON file
PUT    /api/comparisons/:id/revisions/:rev/selections — Bulk update change selections
```

### Client Review (token-based, no auth)
```
GET    /api/review/:token          — Get comparison + latest revision for client review
POST   /api/review/:token/comment  — Add a comment (requires author_name)
POST   /api/review/:token/approve  — Mark as approved
POST   /api/review/:token/request-changes — Mark as changes requested (requires comment)
GET    /api/review/:token/revisions — List revisions (so client can see history)
```

---

## 7. UI Page Structure

```
/                          — Dashboard (comparisons list, connected instances)
/instances                 — Instance management
/instances/new             — Connect new instance
/compare/new               — New comparison (upload or select workflow)
/compare/:id               — Review changes (developer view with checkboxes)
/compare/:id/finalize      — Merge preview + push/download (single screen, not two)
/review/:token             — Client review view (public, no auth, mobile-responsive)
/login                     — Admin login (Supabase Auth)
```

**Note:** Merge preview and push configuration are combined into ONE screen (`/finalize`). The flow is:
1. Review → select changes → click "Finalize"
2. Finalize screen shows:
   - Summary of accepted/rejected changes (final confirmation)
   - Validation warnings (orphan connections, expression errors, missing credentials)
   - If connected instance: push mode selector + credential mapping + "Push" button
   - If upload-only: "Download Merged JSON" button
   - Both flows show "Download Merged JSON" as a secondary action

---

## 8. Error Handling

| Scenario | User-facing message | Technical action |
|----------|-------------------|------------------|
| Invalid JSON uploaded | "This file isn't valid n8n workflow JSON. Check that it was exported from n8n." | Validate against n8n schema (must have nodes, connections) |
| n8n instance unreachable | "Can't connect to {instance}. Check the URL and API key." | Timeout after 10s, mark instance as disconnected |
| API key expired/invalid | "API key rejected by {instance}. Update it in instance settings." | HTTP 401 from n8n API |
| Stale baseline detected | "The live workflow has changed since your baseline was captured. Pull a fresh version to avoid conflicts." | Compare current live hash vs stored before hash |
| Merge produces invalid JSON | "The selected changes create an invalid workflow (e.g., connection to a removed node). Adjust your selections." | Post-merge validation catches orphan connections |
| Orphan expression reference | "Expression in **{node}** references **{missing}** which doesn't exist. This will cause a runtime error." | Regex scan for `$node["..."]` patterns, verify references exist |
| Webhook path conflict | "Webhook **{node}** has a different path than the target. Choose which to keep." | Compare webhook paths between merged JSON and target instance |
| Push fails | "Push failed: {n8n error message}. The original workflow was not modified." | Surface n8n API error. If deactivate-push mode, ensure workflow is reactivated on failure. |
| Push fails mid-deactivate | "Push failed after workflow was deactivated. Reactivating original workflow now." | Auto-reactivate on failure in deactivate-push mode. Surface error after recovery. |
| Review token expired | "This review link has expired. Ask your developer for a new link." | Token checked on page load |
| File too large | "File exceeds 10MB limit. n8n workflows are typically much smaller — check you're uploading the right file." | Client-side + server-side validation |
| No changes detected | "No functional changes detected. The workflows are identical." | After noise filter, check if semantic changelog is empty |
| New credential type needed | "New node **{name}** requires **{credType}** credential. Create it on the target instance first." | Detect credential types in merged JSON not present on target |

---

## 9. Implementation Phases

### Phase 1: Core Engine + Upload Flow (Week 1-2)
- [ ] Project setup (Next.js 14, Supabase, Prisma, TypeScript, shadcn/ui)
- [ ] Database schema migration (instances, comparisons, revisions, comments, selections)
- [ ] Semantic diff engine: jsondiffpatch integration + noise filter + semantic translator
- [ ] Node type registry (n8n type → human-readable name, with camelCase fallback)
- [ ] Deep parameter path humanizer (per-node-type parameter mapping)
- [ ] Code node special handling (extract code content, prepare for code diff view)
- [ ] Sticky note / documentation change categorization
- [ ] Dependency grouper (node + connections as atomic units)
- [ ] JSON upload UI (drag-and-drop, validation, empty state)
- [ ] Review screen — developer view: changelog with checkboxes, details expander, code diff for Code nodes, comparison description field
- [ ] Review screen — mobile-responsive layout from day one
- [ ] Selective merge engine (diff pruner + jsondiffpatch.patch)
- [ ] Post-merge validation (schema, connections, expression references, sub-workflow refs)
- [ ] Finalize screen: merge summary + "Download Merged JSON" button
- [ ] "No changes detected" empty state

### Phase 2: Client Review + Comments (Week 2-3)
- [ ] Shareable review link generation (token-based, 30-day expiry)
- [ ] Client review page: read-only changelog, name entry on first visit, mobile-responsive
- [ ] Comment system: per-change and global, with author name + role
- [ ] "Approve All" and "Request Changes" buttons (request changes requires comment)
- [ ] Comparison status management (draft → pending_review → approved/changes_requested)
- [ ] Revision system: upload new "after" on same comparison, re-diff, preserve comments
- [ ] Revision history dropdown on review page ("New in revision 2" badges)
- [ ] Developer dashboard: see comparison statuses, client comments, pending actions

### Phase 3: n8n Instance Connection + Push (Week 3-4)
- [ ] Instance management (connect with URL + API key, verify, list, encrypted storage)
- [ ] n8n API client (proxy layer — frontend never sees API keys)
- [ ] Workflow picker (list workflows from connected instance via API)
- [ ] "Pull live version as before" flow (real-time fetch, no stale exports)
- [ ] Stale-state detection on push (compare live workflow vs stored baseline)
- [ ] Push engine: all three modes (duplicate, deactivate-push, direct)
- [ ] Credential mapping UI (match credentials between instances, warn on new types)
- [ ] Webhook URL preservation detection + warning
- [ ] Push failure recovery (auto-reactivate on deactivate-push failure)
- [ ] Post-push confirmation screen + history recording

### Phase 4: Polish + Production Hardening (Week 4-5)
- [ ] Dashboard polish: comparison history, filtering by instance/status/date, search by workflow name
- [ ] Audit trail: exportable history for client reporting
- [ ] Error handling for ALL edge cases (see Error Handling table)
- [ ] Security review: encryption audit, input validation, token security, rate limiting
- [ ] Performance: large workflow handling (100+ nodes), diff computation timeout protection
- [ ] UI polish: loading states, skeleton screens, animations, toast notifications
- [ ] Deployment: Vercel production + Supabase production + environment variables + monitoring

---

## 10. n8n Node Type Registry (Extensible)

This registry maps internal n8n node types to human-readable display names. It is used by the semantic translator.

```typescript
const NODE_TYPE_REGISTRY: Record<string, string> = {
  // Triggers
  'n8n-nodes-base.webhook': 'Webhook Trigger',
  'n8n-nodes-base.scheduleTrigger': 'Schedule Trigger',
  'n8n-nodes-base.emailReadImap': 'Email Trigger (IMAP)',
  'n8n-nodes-base.manualTrigger': 'Manual Trigger',

  // Flow Control
  'n8n-nodes-base.if': 'IF / Router',
  'n8n-nodes-base.switch': 'Switch',
  'n8n-nodes-base.merge': 'Merge',
  'n8n-nodes-base.splitInBatches': 'Split in Batches',
  'n8n-nodes-base.wait': 'Wait',
  'n8n-nodes-base.noOp': 'No Operation',

  // Data Transformation
  'n8n-nodes-base.set': 'Set Values',
  'n8n-nodes-base.code': 'Code (JavaScript/Python)',
  'n8n-nodes-base.functionItem': 'Function Item',
  'n8n-nodes-base.itemLists': 'Item Lists',
  'n8n-nodes-base.dateTime': 'Date & Time',
  'n8n-nodes-base.crypto': 'Crypto',
  'n8n-nodes-base.xml': 'XML',
  'n8n-nodes-base.html': 'HTML Extract',
  'n8n-nodes-base.markdown': 'Markdown',

  // HTTP / API
  'n8n-nodes-base.httpRequest': 'HTTP Request',
  'n8n-nodes-base.respondToWebhook': 'Respond to Webhook',
  'n8n-nodes-base.graphql': 'GraphQL',

  // Communication
  'n8n-nodes-base.emailSend': 'Send Email',
  'n8n-nodes-base.slack': 'Slack',
  'n8n-nodes-base.telegramTrigger': 'Telegram Trigger',
  'n8n-nodes-base.telegram': 'Telegram',
  'n8n-nodes-base.discord': 'Discord',
  'n8n-nodes-base.microsoftTeams': 'Microsoft Teams',

  // Databases
  'n8n-nodes-base.postgres': 'PostgreSQL',
  'n8n-nodes-base.mySql': 'MySQL',
  'n8n-nodes-base.mongoDb': 'MongoDB',
  'n8n-nodes-base.redis': 'Redis',

  // Cloud Services
  'n8n-nodes-base.googleSheets': 'Google Sheets',
  'n8n-nodes-base.googleDrive': 'Google Drive',
  'n8n-nodes-base.googleCalendar': 'Google Calendar',
  'n8n-nodes-base.airtable': 'Airtable',
  'n8n-nodes-base.notion': 'Notion',

  // AI / LLM
  '@n8n/n8n-nodes-langchain.openAi': 'OpenAI',
  '@n8n/n8n-nodes-langchain.anthropic': 'Anthropic (Claude)',

  // CRM / Business
  'n8n-nodes-base.hubspot': 'HubSpot',
  'n8n-nodes-base.salesforce': 'Salesforce',
  'n8n-nodes-base.pipedrive': 'Pipedrive',

  // File / Storage
  'n8n-nodes-base.readWriteFile': 'Read/Write File',
  'n8n-nodes-base.ftp': 'FTP',
  'n8n-nodes-base.s3': 'AWS S3',

  // Utility
  'n8n-nodes-base.executeWorkflow': 'Execute Sub-Workflow',
  'n8n-nodes-base.executeWorkflowTrigger': 'Sub-Workflow Trigger',
  'n8n-nodes-base.stickyNote': 'Sticky Note',
  'n8n-nodes-base.errorTrigger': 'Error Trigger',
};

// Fallback: parse type string for unknown nodes
// 'n8n-nodes-base.googleSheets' → 'Google Sheets'
// '@n8n/n8n-nodes-langchain.chainLlm' → 'Chain LLM'
function getNodeDisplayName(type: string): string {
  if (NODE_TYPE_REGISTRY[type]) return NODE_TYPE_REGISTRY[type];

  // Extract last segment and convert camelCase to Title Case
  const lastSegment = type.split('.').pop() || type;
  return lastSegment
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (str) => str.toUpperCase())
    .trim();
}
```

---

## 11. Key Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Diff library | jsondiffpatch | Provides both diff AND patch (merge). Array diffing with LCS. Active maintenance. MIT. |
| Framework | Next.js App Router | Frontend + API in one project. Vercel deployment. React Server Components for performance. |
| Database | Supabase (PostgreSQL) | Production-grade. Auth, storage, realtime built in. Free tier generous. Already in Utkarsh's stack. |
| ORM | Prisma | Type-safe. Migration management. Works with Supabase Postgres. |
| State management | Zustand | Lightweight alternative to Redux. Perfect for this scale. |
| Encryption | AES-256-GCM (Node.js crypto) | Industry standard for API key encryption. No external dependency. |
| Client auth | Token-based (no login) | Clients should not need accounts. One link, one click. |
| Push default | "Push as duplicate" | Safest option. Mirrors the existing manual workaround. |
| Hosting | Vercel | Free tier. HTTPS. Edge functions. Perfect for Next.js. |

---

## 12. Future Considerations (Not in Scope Now)

These are documented for completeness but explicitly NOT part of the current build:

- **Automatic change detection:** Webhook/polling to detect when a connected workflow changes, auto-create comparison
- **Multi-user access:** Multiple developers and clients with role-based permissions
- **Workflow visual diff:** Side-by-side canvas rendering showing node graph changes visually
- **Automated testing:** Run the merged workflow with test data before pushing
- **Make.com / Zapier support:** Same concept for other automation platforms
- **CLI tool:** Command-line interface for CI/CD pipelines
- **Slack/email notifications:** Notify when client approves or comments
- **SaaS pricing + billing:** If this becomes a product to sell externally

---

## Appendix A: Research Findings

### Market Gap
- n8n has 230,000+ users, 70k GitHub stars, $2.5B valuation
- Built-in version control locked behind 800 EUR/month Business plan
- Every competitor (Zapier, Make, Activepieces, Windmill) includes versioning at all tiers
- Community has requested this feature for 3+ years (2020-2023 thread)
- No dedicated SaaS product exists for this use case

### Existing Tools (Not Sufficient)
| Tool | Limitation |
|------|-----------|
| n8n 2 Git (Chrome extension, 5 EUR/mo) | Browser-dependent, no review UI, no merge, no client sharing |
| Workflow Repos8r (n8n template) | Built as an n8n workflow, no semantic diff, no client review |
| n8n Workflows Comparator (CLI, MIT) | 2 GitHub stars, CLI-only, no merge, no push, no UI |
| Community backup templates | Periodic snapshots, not version control |

### n8n API Coverage
Full REST API available (all plans including Community):
- Read/write workflows, credentials, executions, tags, variables
- API key authentication
- OpenAPI 3.0 specification
- All endpoints needed for this product are available on the free tier
