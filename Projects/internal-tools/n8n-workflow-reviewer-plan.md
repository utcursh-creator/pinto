# n8n Workflow Reviewer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-grade web app for human-readable n8n workflow change review, selective merge, and push-to-production — following the full PRD at `Projects/internal-tools/n8n-workflow-reviewer-prd.md`.

**Architecture:** Next.js 14 App Router with server-side API routes proxying all n8n calls. Core diff engine runs server-side via jsondiffpatch with a custom semantic translation layer. Supabase provides PostgreSQL storage + auth. Client review is token-based (no login). All n8n API keys encrypted at rest with AES-256-GCM.

**Tech Stack:** Next.js 14 (App Router), TypeScript 5, shadcn/ui, Tailwind CSS, jsondiffpatch 0.6.x, react-diff-viewer-continued 4.x, react-dropzone 14.x, Prisma 6.x, Supabase (PostgreSQL + Auth), Zustand 4.x, Vercel

**Project Location:** `Projects/internal-tools/n8n-workflow-reviewer/`

---

## Phase 1: Core Engine + Upload Flow (Tasks 1–18)

### Task 1: Project Scaffolding

**Files:**
- Create: `n8n-workflow-reviewer/` (entire Next.js project)
- Create: `n8n-workflow-reviewer/.env.local`
- Create: `n8n-workflow-reviewer/.env.example`

**Step 1: Scaffold Next.js 14 project**

```bash
cd "Projects/internal-tools"
npx create-next-app@14 n8n-workflow-reviewer --typescript --tailwind --eslint --app --src-dir --import-alias "@/*"
cd n8n-workflow-reviewer
```

**Step 2: Initialize shadcn/ui**

```bash
npx shadcn@latest init
# Select: New York style, Zinc base color, CSS variables: yes
```

**Step 3: Install core dependencies**

```bash
npm install jsondiffpatch@^0.6 react-diff-viewer-continued@^4 react-dropzone@^14 zustand@^4 prisma@^6 @prisma/client@^6 uuid
npm install -D @types/uuid
```

**Step 4: Add shadcn components we'll need**

```bash
npx shadcn@latest add button card dialog tabs checkbox badge separator dropdown-menu input textarea label toast alert scroll-area sheet select tooltip
```

**Step 5: Create folder structure**

```
src/
├── app/
│   ├── (dashboard)/
│   │   ├── page.tsx                    # Dashboard
│   │   ├── instances/
│   │   │   ├── page.tsx                # Instance list
│   │   │   └── new/page.tsx            # Connect new instance
│   │   └── compare/
│   │       ├── new/page.tsx            # New comparison
│   │       └── [id]/
│   │           ├── page.tsx            # Review changes (developer)
│   │           └── finalize/page.tsx   # Merge + push/download
│   ├── review/
│   │   └── [token]/page.tsx            # Client review (public)
│   ├── login/page.tsx                  # Auth
│   ├── api/
│   │   ├── instances/
│   │   ├── comparisons/
│   │   └── review/
│   ├── layout.tsx
│   └── globals.css
├── lib/
│   ├── engine/                         # Core diff/merge engine
│   │   ├── diff.ts                     # jsondiffpatch wrapper
│   │   ├── noise-filter.ts             # Remove position, pinData, etc.
│   │   ├── semantic-translator.ts      # Raw diff → human-readable
│   │   ├── node-registry.ts            # n8n type → display name
│   │   ├── parameter-humanizer.ts      # Deep param path → readable
│   │   ├── dependency-grouper.ts       # Bundle node + connections
│   │   ├── security-flagger.ts         # Flag credential/webhook changes
│   │   ├── merge.ts                    # Selective merge (diff pruner + patch)
│   │   ├── validator.ts               # Post-merge validation
│   │   └── types.ts                    # All engine types
│   ├── n8n/
│   │   ├── api-client.ts              # n8n REST API wrapper
│   │   ├── types.ts                    # n8n JSON types
│   │   └── validation.ts              # n8n JSON schema validation
│   ├── crypto.ts                       # AES-256-GCM encryption
│   ├── db.ts                           # Prisma client singleton
│   └── utils.ts                        # Shared utilities
├── components/
│   ├── ui/                             # shadcn components (auto-generated)
│   ├── changelog/                      # Review UI components
│   │   ├── change-card.tsx
│   │   ├── change-group.tsx
│   │   ├── changelog-list.tsx
│   │   ├── code-diff-viewer.tsx
│   │   ├── summary-bar.tsx
│   │   └── category-section.tsx
│   ├── upload/
│   │   ├── json-dropzone.tsx
│   │   └── upload-form.tsx
│   ├── review/
│   │   ├── comment-thread.tsx
│   │   ├── name-entry.tsx
│   │   └── review-actions.tsx
│   ├── finalize/
│   │   ├── merge-summary.tsx
│   │   ├── validation-warnings.tsx
│   │   ├── push-config.tsx
│   │   └── credential-mapper.tsx
│   ├── instances/
│   │   ├── instance-card.tsx
│   │   └── instance-form.tsx
│   └── layout/
│       ├── sidebar.tsx
│       ├── header.tsx
│       └── nav.tsx
├── store/
│   ├── comparison-store.ts             # Zustand store for active comparison
│   └── ui-store.ts                     # UI state
└── __tests__/
    ├── engine/
    │   ├── diff.test.ts
    │   ├── noise-filter.test.ts
    │   ├── semantic-translator.test.ts
    │   ├── node-registry.test.ts
    │   ├── parameter-humanizer.test.ts
    │   ├── dependency-grouper.test.ts
    │   ├── security-flagger.test.ts
    │   ├── merge.test.ts
    │   └── validator.test.ts
    ├── n8n/
    │   └── validation.test.ts
    └── fixtures/
        ├── simple-workflow-before.json
        ├── simple-workflow-after.json
        ├── complex-workflow-before.json
        └── complex-workflow-after.json
```

Create the directories:

```bash
mkdir -p src/lib/engine src/lib/n8n src/components/{changelog,upload,review,finalize,instances,layout} src/store src/__tests__/{engine,n8n,fixtures} src/app/api/{instances,comparisons,review}
```

**Step 6: Create .env.example**

```env
# Supabase
DATABASE_URL="postgres://postgres.PROJECT:PASSWORD@aws-0-REGION.pooler.supabase.com:6543/postgres?pgbouncer=true&connection_limit=1"
DIRECT_URL="postgres://postgres.PROJECT:PASSWORD@db.PROJECT.supabase.co:5432/postgres"
NEXT_PUBLIC_SUPABASE_URL="https://PROJECT.supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="your-anon-key"
SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"

# Encryption
ENCRYPTION_KEY="generate-a-32-byte-hex-key"

# App
NEXT_PUBLIC_APP_URL="http://localhost:3000"
```

**Step 7: Configure testing**

```bash
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom
```

Create `vitest.config.ts`:
```typescript
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/__tests__/setup.ts'],
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
})
```

Create `src/__tests__/setup.ts`:
```typescript
import '@testing-library/jest-dom'
```

Add to `package.json` scripts:
```json
{
  "scripts": {
    "test": "vitest",
    "test:run": "vitest run",
    "test:ui": "vitest --ui"
  }
}
```

**Step 8: Verify project runs**

```bash
npm run dev
# Should start on localhost:3000
npm run test:run
# Should show 0 tests (no test files yet)
```

**Step 9: Commit**

```bash
git init
git add .
git commit -m "feat: scaffold Next.js 14 project with shadcn, testing, and folder structure"
```

---

### Task 2: n8n Workflow Types & Validation

**Files:**
- Create: `src/lib/n8n/types.ts`
- Create: `src/lib/n8n/validation.ts`
- Test: `src/__tests__/n8n/validation.test.ts`
- Create: `src/__tests__/fixtures/simple-workflow-before.json`
- Create: `src/__tests__/fixtures/simple-workflow-after.json`

**Step 1: Create test fixtures — real n8n workflow JSONs**

`src/__tests__/fixtures/simple-workflow-before.json`:
```json
{
  "name": "Customer Onboarding",
  "nodes": [
    {
      "id": "node-1",
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [250, 300],
      "parameters": {
        "httpMethod": "POST",
        "path": "onboard"
      },
      "webhookId": "webhook-uuid-1"
    },
    {
      "id": "node-2",
      "name": "Set Customer Data",
      "type": "n8n-nodes-base.set",
      "typeVersion": 1,
      "position": [450, 300],
      "parameters": {
        "values": {
          "string": [
            { "name": "fullName", "value": "={{ $json.name }}" },
            { "name": "email", "value": "={{ $json.email }}" }
          ]
        }
      }
    },
    {
      "id": "node-3",
      "name": "Send Welcome Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 1,
      "position": [650, 300],
      "parameters": {
        "fromEmail": "welcome@company.com",
        "toEmail": "={{ $json.email }}",
        "subject": "Welcome!",
        "text": "Hi {{ $json.fullName }}, welcome aboard!"
      },
      "credentials": {
        "smtp": {
          "id": "cred-1",
          "name": "Company SMTP"
        }
      }
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [[{ "node": "Set Customer Data", "type": "main", "index": 0 }]]
    },
    "Set Customer Data": {
      "main": [[{ "node": "Send Welcome Email", "type": "main", "index": 0 }]]
    }
  },
  "active": true,
  "settings": { "executionOrder": "v1" },
  "versionId": "v1-abc",
  "id": "wf-123",
  "tags": [],
  "pinData": {},
  "meta": { "instanceId": "instance-1" }
}
```

`src/__tests__/fixtures/simple-workflow-after.json`:
```json
{
  "name": "Customer Onboarding v2",
  "nodes": [
    {
      "id": "node-1",
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [250, 320],
      "parameters": {
        "httpMethod": "POST",
        "path": "onboard-v2"
      },
      "webhookId": "webhook-uuid-1"
    },
    {
      "id": "node-2",
      "name": "Set Customer Data",
      "type": "n8n-nodes-base.set",
      "typeVersion": 1,
      "position": [450, 320],
      "parameters": {
        "values": {
          "string": [
            { "name": "fullName", "value": "={{ $json.name }}" },
            { "name": "email", "value": "={{ $json.email }}" },
            { "name": "company", "value": "={{ $json.company }}" }
          ]
        }
      }
    },
    {
      "id": "node-3",
      "name": "Send Welcome Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 1,
      "position": [850, 320],
      "parameters": {
        "fromEmail": "hello@company.com",
        "toEmail": "={{ $json.email }}",
        "subject": "Welcome to {{ $json.company }}!",
        "text": "Hi {{ $json.fullName }}, welcome aboard!"
      },
      "credentials": {
        "smtp": {
          "id": "cred-2",
          "name": "New SMTP Provider"
        }
      }
    },
    {
      "id": "node-4",
      "name": "Add to CRM",
      "type": "n8n-nodes-base.hubspot",
      "typeVersion": 1,
      "position": [850, 500],
      "parameters": {
        "resource": "contact",
        "operation": "create",
        "email": "={{ $json.email }}",
        "additionalFields": {
          "company": "={{ $json.company }}"
        }
      },
      "credentials": {
        "hubspotApi": {
          "id": "cred-3",
          "name": "HubSpot API"
        }
      }
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [[{ "node": "Set Customer Data", "type": "main", "index": 0 }]]
    },
    "Set Customer Data": {
      "main": [
        [
          { "node": "Send Welcome Email", "type": "main", "index": 0 },
          { "node": "Add to CRM", "type": "main", "index": 0 }
        ]
      ]
    }
  },
  "active": true,
  "settings": { "executionOrder": "v1" },
  "versionId": "v2-def",
  "id": "wf-123",
  "tags": [],
  "pinData": { "Set Customer Data": [{ "json": { "name": "Test" } }] },
  "meta": { "instanceId": "instance-1" }
}
```

**Step 2: Write failing tests for validation**

`src/__tests__/n8n/validation.test.ts`:
```typescript
import { describe, it, expect } from 'vitest'
import { validateN8nWorkflow, type N8nValidationResult } from '@/lib/n8n/validation'
import beforeJson from '../fixtures/simple-workflow-before.json'

describe('validateN8nWorkflow', () => {
  it('accepts a valid n8n workflow JSON', () => {
    const result = validateN8nWorkflow(beforeJson)
    expect(result.valid).toBe(true)
    expect(result.errors).toHaveLength(0)
  })

  it('rejects JSON missing nodes array', () => {
    const result = validateN8nWorkflow({ name: 'test', connections: {} })
    expect(result.valid).toBe(false)
    expect(result.errors).toContain('Missing required field: nodes')
  })

  it('rejects JSON missing connections object', () => {
    const result = validateN8nWorkflow({ name: 'test', nodes: [] })
    expect(result.valid).toBe(false)
    expect(result.errors).toContain('Missing required field: connections')
  })

  it('rejects non-object input', () => {
    const result = validateN8nWorkflow('not json')
    expect(result.valid).toBe(false)
  })

  it('rejects null input', () => {
    const result = validateN8nWorkflow(null)
    expect(result.valid).toBe(false)
  })

  it('validates nodes have required fields (id, name, type)', () => {
    const result = validateN8nWorkflow({
      name: 'test',
      nodes: [{ id: '1' }], // missing name and type
      connections: {}
    })
    expect(result.valid).toBe(false)
    expect(result.errors.some((e: string) => e.includes('name'))).toBe(true)
  })
})
```

**Step 3: Run tests — verify they fail**

```bash
npm run test:run -- src/__tests__/n8n/validation.test.ts
```

Expected: FAIL (module not found)

**Step 4: Implement types**

`src/lib/n8n/types.ts`:
```typescript
export interface N8nNode {
  id: string
  name: string
  type: string
  typeVersion: number
  position: [number, number]
  parameters: Record<string, unknown>
  credentials?: Record<string, { id: string; name: string }>
  disabled?: boolean
  notes?: string
  webhookId?: string
}

export interface N8nConnection {
  node: string
  type: string
  index: number
}

export interface N8nWorkflow {
  name: string
  nodes: N8nNode[]
  connections: Record<string, { main: N8nConnection[][] }>
  active?: boolean
  settings?: Record<string, unknown>
  versionId?: string
  id?: string
  tags?: unknown[]
  pinData?: Record<string, unknown>
  meta?: Record<string, unknown>
}
```

**Step 5: Implement validation**

`src/lib/n8n/validation.ts`:
```typescript
import type { N8nWorkflow } from './types'

export interface N8nValidationResult {
  valid: boolean
  errors: string[]
  workflow?: N8nWorkflow
}

export function validateN8nWorkflow(input: unknown): N8nValidationResult {
  const errors: string[] = []

  if (!input || typeof input !== 'object') {
    return { valid: false, errors: ['Input is not a valid JSON object'] }
  }

  const obj = input as Record<string, unknown>

  if (!Array.isArray(obj.nodes)) {
    errors.push('Missing required field: nodes')
  }

  if (!obj.connections || typeof obj.connections !== 'object' || Array.isArray(obj.connections)) {
    errors.push('Missing required field: connections')
  }

  // Validate individual nodes
  if (Array.isArray(obj.nodes)) {
    for (let i = 0; i < obj.nodes.length; i++) {
      const node = obj.nodes[i] as Record<string, unknown>
      if (!node.name) errors.push(`Node at index ${i} missing required field: name`)
      if (!node.type) errors.push(`Node at index ${i} missing required field: type`)
      if (!node.id) errors.push(`Node at index ${i} missing required field: id`)
    }
  }

  if (errors.length > 0) {
    return { valid: false, errors }
  }

  return { valid: true, errors: [], workflow: obj as unknown as N8nWorkflow }
}
```

**Step 6: Run tests — verify they pass**

```bash
npm run test:run -- src/__tests__/n8n/validation.test.ts
```

Expected: ALL PASS

**Step 7: Commit**

```bash
git add src/lib/n8n/ src/__tests__/n8n/ src/__tests__/fixtures/
git commit -m "feat: add n8n workflow types and JSON validation"
```

---

### Task 3: Node Type Registry

**Files:**
- Create: `src/lib/engine/node-registry.ts`
- Test: `src/__tests__/engine/node-registry.test.ts`

**Step 1: Write failing tests**

`src/__tests__/engine/node-registry.test.ts`:
```typescript
import { describe, it, expect } from 'vitest'
import { getNodeDisplayName } from '@/lib/engine/node-registry'

describe('getNodeDisplayName', () => {
  it('returns registered name for known types', () => {
    expect(getNodeDisplayName('n8n-nodes-base.httpRequest')).toBe('HTTP Request')
    expect(getNodeDisplayName('n8n-nodes-base.if')).toBe('IF / Router')
    expect(getNodeDisplayName('n8n-nodes-base.webhook')).toBe('Webhook Trigger')
    expect(getNodeDisplayName('n8n-nodes-base.code')).toBe('Code (JavaScript/Python)')
    expect(getNodeDisplayName('n8n-nodes-base.slack')).toBe('Slack')
  })

  it('returns registered name for langchain nodes', () => {
    expect(getNodeDisplayName('@n8n/n8n-nodes-langchain.openAi')).toBe('OpenAI')
    expect(getNodeDisplayName('@n8n/n8n-nodes-langchain.anthropic')).toBe('Anthropic (Claude)')
  })

  it('falls back to camelCase parsing for unknown types', () => {
    expect(getNodeDisplayName('n8n-nodes-base.googleSheets')).toBe('Google Sheets')
    expect(getNodeDisplayName('n8n-nodes-base.microsoftOutlook')).toBe('Microsoft Outlook')
  })

  it('handles edge cases in fallback', () => {
    expect(getNodeDisplayName('n8n-nodes-base.ftp')).toBe('FTP')
    expect(getNodeDisplayName('unknown.type')).toBe('Type')
    expect(getNodeDisplayName('singleSegment')).toBe('Single Segment')
  })
})
```

**Step 2: Run — verify fail**

```bash
npm run test:run -- src/__tests__/engine/node-registry.test.ts
```

**Step 3: Implement**

`src/lib/engine/node-registry.ts`:
Copy the full NODE_TYPE_REGISTRY and `getNodeDisplayName` from PRD Section 10 (lines 717-802).

**Step 4: Run — verify pass. Commit.**

```bash
git commit -m "feat: add n8n node type registry with camelCase fallback"
```

---

### Task 4: Parameter Path Humanizer

**Files:**
- Create: `src/lib/engine/parameter-humanizer.ts`
- Test: `src/__tests__/engine/parameter-humanizer.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { humanizeParameterPath } from '@/lib/engine/parameter-humanizer'

describe('humanizeParameterPath', () => {
  it('humanizes common parameter paths', () => {
    expect(humanizeParameterPath('parameters.url')).toBe('URL')
    expect(humanizeParameterPath('parameters.method')).toBe('HTTP Method')
    expect(humanizeParameterPath('parameters.resource')).toBe('Resource')
    expect(humanizeParameterPath('parameters.operation')).toBe('Operation')
  })

  it('humanizes header/body/query parameters with names', () => {
    expect(humanizeParameterPath(
      'parameters.headerParameters.parameters.0.value',
      { paramName: 'Authorization' }
    )).toBe("Header 'Authorization' value")

    expect(humanizeParameterPath(
      'parameters.bodyParameters.parameters.0.value',
      { paramName: 'payload' }
    )).toBe("Body param 'payload' value")

    expect(humanizeParameterPath(
      'parameters.queryParameters.parameters.0.value',
      { paramName: 'page' }
    )).toBe("Query param 'page' value")
  })

  it('humanizes authentication paths', () => {
    expect(humanizeParameterPath('parameters.authentication.oauth2')).toBe('Authentication: Oauth2')
  })

  it('humanizes condition paths', () => {
    expect(humanizeParameterPath('parameters.conditions.conditions.0.value')).toBe('Condition 1: Value')
  })

  it('falls back to last 2 segments in Title Case', () => {
    expect(humanizeParameterPath('parameters.options.batching.batchSize')).toBe('Batching: Batch Size')
    expect(humanizeParameterPath('parameters.options.redirect.follow')).toBe('Setting: Follow Redirects')
  })

  it('identifies code parameters', () => {
    expect(humanizeParameterPath('parameters.jsCode')).toBe('__CODE__')
    expect(humanizeParameterPath('parameters.code')).toBe('__CODE__')
    expect(humanizeParameterPath('parameters.pythonCode')).toBe('__CODE__')
  })
})
```

**Step 2: Run — fail. Step 3: Implement.**

`src/lib/engine/parameter-humanizer.ts`:
```typescript
const KNOWN_PATHS: Record<string, string> = {
  'parameters.url': 'URL',
  'parameters.method': 'HTTP Method',
  'parameters.resource': 'Resource',
  'parameters.operation': 'Operation',
  'parameters.jsCode': '__CODE__',
  'parameters.code': '__CODE__',
  'parameters.pythonCode': '__CODE__',
}

const REDIRECT_PATHS: Record<string, string> = {
  'parameters.options.redirect.follow': 'Setting: Follow Redirects',
}

interface HumanizeContext {
  paramName?: string
}

export function humanizeParameterPath(path: string, context?: HumanizeContext): string {
  // Exact match
  if (KNOWN_PATHS[path]) return KNOWN_PATHS[path]
  if (REDIRECT_PATHS[path]) return REDIRECT_PATHS[path]

  // Header/body/query parameters
  const headerMatch = path.match(/^parameters\.headerParameters\.parameters\.\d+\.(\w+)$/)
  if (headerMatch) {
    return context?.paramName
      ? `Header '${context.paramName}' ${headerMatch[1]}`
      : `Header ${toTitleCase(headerMatch[1])}`
  }

  const bodyMatch = path.match(/^parameters\.bodyParameters\.parameters\.\d+\.(\w+)$/)
  if (bodyMatch) {
    return context?.paramName
      ? `Body param '${context.paramName}' ${bodyMatch[1]}`
      : `Body param ${toTitleCase(bodyMatch[1])}`
  }

  const queryMatch = path.match(/^parameters\.queryParameters\.parameters\.\d+\.(\w+)$/)
  if (queryMatch) {
    return context?.paramName
      ? `Query param '${context.paramName}' ${queryMatch[1]}`
      : `Query param ${toTitleCase(queryMatch[1])}`
  }

  // Authentication
  const authMatch = path.match(/^parameters\.authentication\.(.+)$/)
  if (authMatch) {
    return `Authentication: ${toTitleCase(authMatch[1])}`
  }

  // Conditions
  const conditionMatch = path.match(/^parameters\.conditions\.conditions\.(\d+)\.(\w+)$/)
  if (conditionMatch) {
    return `Condition ${Number(conditionMatch[1]) + 1}: ${toTitleCase(conditionMatch[2])}`
  }

  // Fallback: last 2 segments in Title Case
  const segments = path.split('.')
  if (segments.length >= 2) {
    const last2 = segments.slice(-2)
    return `${toTitleCase(last2[0])}: ${toTitleCase(last2[1])}`
  }

  return toTitleCase(segments[segments.length - 1])
}

function toTitleCase(str: string): string {
  return str
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (s) => s.toUpperCase())
    .trim()
}
```

**Step 4: Run — pass. Commit.**

```bash
git commit -m "feat: add deep parameter path humanizer"
```

---

### Task 5: Noise Filter

**Files:**
- Create: `src/lib/engine/noise-filter.ts`
- Test: `src/__tests__/engine/noise-filter.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { filterNoise } from '@/lib/engine/noise-filter'

describe('filterNoise', () => {
  it('removes position changes from node diffs', () => {
    const delta = {
      nodes: {
        _t: 'a',
        0: { position: [[250, 300], [250, 320]] }
      }
    }
    const filtered = filterNoise(delta)
    // Node 0 had ONLY position change, so it should be removed entirely
    expect(filtered.nodes?.['0']).toBeUndefined()
  })

  it('removes versionId changes', () => {
    const delta = { versionId: ['v1-abc', 'v2-def'] }
    const filtered = filterNoise(delta)
    expect(filtered.versionId).toBeUndefined()
  })

  it('removes pinData changes', () => {
    const delta = { pinData: { someNode: [{ json: {} }] } }
    const filtered = filterNoise(delta)
    expect(filtered.pinData).toBeUndefined()
  })

  it('removes meta changes', () => {
    const delta = { meta: { instanceId: ['a', 'b'] } }
    const filtered = filterNoise(delta)
    expect(filtered.meta).toBeUndefined()
  })

  it('keeps functional changes on nodes', () => {
    const delta = {
      nodes: {
        _t: 'a',
        0: {
          position: [[250, 300], [250, 320]],
          parameters: { url: ['old.com', 'new.com'] }
        }
      }
    }
    const filtered = filterNoise(delta)
    expect(filtered.nodes?.['0']?.parameters).toBeDefined()
    expect(filtered.nodes?.['0']?.position).toBeUndefined()
  })

  it('removes id field changes', () => {
    const delta = {
      nodes: {
        _t: 'a',
        0: { id: ['old-uuid', 'new-uuid'] }
      }
    }
    const filtered = filterNoise(delta)
    expect(filtered.nodes?.['0']).toBeUndefined()
  })

  it('returns null if all changes are noise', () => {
    const delta = {
      versionId: ['v1', 'v2'],
      meta: { x: ['a', 'b'] },
      pinData: {}
    }
    const filtered = filterNoise(delta)
    expect(filtered).toBeNull()
  })
})
```

**Step 2: Run — fail. Step 3: Implement.**

`src/lib/engine/noise-filter.ts`:
```typescript
const TOP_LEVEL_NOISE = new Set(['versionId', 'pinData', 'meta', 'id'])
const NODE_LEVEL_NOISE = new Set(['position', 'id'])

export function filterNoise(delta: Record<string, unknown> | null): Record<string, unknown> | null {
  if (!delta) return null

  const filtered: Record<string, unknown> = {}

  for (const [key, value] of Object.entries(delta)) {
    if (TOP_LEVEL_NOISE.has(key)) continue

    if (key === 'nodes' && value && typeof value === 'object') {
      const nodesDelta = filterNodesDelta(value as Record<string, unknown>)
      if (nodesDelta) filtered.nodes = nodesDelta
    } else {
      filtered[key] = value
    }
  }

  return Object.keys(filtered).length === 0 ? null : filtered
}

function filterNodesDelta(nodesDelta: Record<string, unknown>): Record<string, unknown> | null {
  const filtered: Record<string, unknown> = { _t: 'a' }

  for (const [key, value] of Object.entries(nodesDelta)) {
    if (key === '_t') continue

    if (value && typeof value === 'object' && !Array.isArray(value)) {
      const nodeFiltered = filterNodeFields(value as Record<string, unknown>)
      if (nodeFiltered && Object.keys(nodeFiltered).length > 0) {
        filtered[key] = nodeFiltered
      }
    } else {
      // Array values = added/removed nodes — always keep
      filtered[key] = value
    }
  }

  const hasChanges = Object.keys(filtered).some(k => k !== '_t')
  return hasChanges ? filtered : null
}

function filterNodeFields(nodeDelta: Record<string, unknown>): Record<string, unknown> | null {
  const filtered: Record<string, unknown> = {}

  for (const [key, value] of Object.entries(nodeDelta)) {
    if (NODE_LEVEL_NOISE.has(key)) continue
    filtered[key] = value
  }

  return Object.keys(filtered).length === 0 ? null : filtered
}
```

**Step 4: Run — pass. Commit.**

```bash
git commit -m "feat: add noise filter for position, pinData, meta, versionId"
```

---

### Task 6: Engine Types

**Files:**
- Create: `src/lib/engine/types.ts`

**Step 1: Define all engine types used across the diff pipeline**

`src/lib/engine/types.ts`:
```typescript
export type ChangeCategory =
  | 'security'
  | 'added_node'
  | 'removed_node'
  | 'modified_node'
  | 'connection_change'
  | 'workflow_settings'
  | 'documentation'

export interface SemanticChange {
  id: string
  category: ChangeCategory
  description: string
  nodeId?: string
  nodeName?: string
  nodeType?: string
  details?: {
    field?: string
    oldValue?: unknown
    newValue?: unknown
    isCode?: boolean
    codeLanguage?: 'javascript' | 'python'
    oldCode?: string
    newCode?: string
  }
}

export interface ChangeGroup {
  id: string
  category: ChangeCategory
  title: string
  description: string
  changes: SemanticChange[]
  isAtomic: boolean // Must accept/reject all together
}

export interface SemanticChangelog {
  groups: ChangeGroup[]
  summary: {
    addedNodes: number
    removedNodes: number
    modifiedNodes: number
    connectionChanges: number
    settingsChanges: number
    securityFlags: number
    documentationChanges: number
  }
  isEmpty: boolean
}

export interface MergeResult {
  mergedJson: Record<string, unknown>
  warnings: MergeWarning[]
  valid: boolean
}

export interface MergeWarning {
  type: 'orphan_connection' | 'expression_reference' | 'sub_workflow' | 'credential_missing'
  message: string
  severity: 'error' | 'warning'
  nodeId?: string
  nodeName?: string
}

export interface ValidationResult {
  valid: boolean
  errors: string[]
  warnings: MergeWarning[]
}
```

**Step 2: Commit**

```bash
git commit -m "feat: add engine type definitions for changelog, groups, merge"
```

---

### Task 7: jsondiffpatch Integration + Diff Pipeline

**Files:**
- Create: `src/lib/engine/diff.ts`
- Test: `src/__tests__/engine/diff.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { computeDiff, type DiffResult } from '@/lib/engine/diff'
import beforeJson from '../fixtures/simple-workflow-before.json'
import afterJson from '../fixtures/simple-workflow-after.json'

describe('computeDiff', () => {
  it('detects added nodes', () => {
    const result = computeDiff(beforeJson, afterJson)
    expect(result.rawDelta).toBeDefined()
    expect(result.filteredDelta).toBeDefined()
  })

  it('returns null filteredDelta when workflows are identical', () => {
    const result = computeDiff(beforeJson, beforeJson)
    expect(result.filteredDelta).toBeNull()
    expect(result.rawDelta).toBeUndefined()
  })

  it('filters out position-only changes', () => {
    const modified = JSON.parse(JSON.stringify(beforeJson))
    modified.nodes[0].position = [999, 999]
    const result = computeDiff(beforeJson, modified)
    // Position change should be filtered
    expect(result.filteredDelta).toBeNull()
  })

  it('detects parameter changes after noise filtering', () => {
    const modified = JSON.parse(JSON.stringify(beforeJson))
    modified.nodes[2].parameters.fromEmail = 'new@company.com'
    const result = computeDiff(beforeJson, modified)
    expect(result.filteredDelta).not.toBeNull()
  })
})
```

**Step 2: Run — fail. Step 3: Implement.**

`src/lib/engine/diff.ts`:
```typescript
import * as jsondiffpatch from 'jsondiffpatch'
import { filterNoise } from './noise-filter'

const diffpatcher = jsondiffpatch.create({
  objectHash: (obj: unknown) => {
    const o = obj as Record<string, unknown>
    return (o.id as string) || (o.name as string)
  },
  propertyFilter: (_name: string) => true, // Keep all — noise filter handles removal
  cloneDiffValues: true,
})

export interface DiffResult {
  rawDelta: jsondiffpatch.Delta | undefined
  filteredDelta: Record<string, unknown> | null
}

export function computeDiff(
  before: Record<string, unknown>,
  after: Record<string, unknown>
): DiffResult {
  const rawDelta = diffpatcher.diff(before, after)

  if (!rawDelta) {
    return { rawDelta: undefined, filteredDelta: null }
  }

  const filteredDelta = filterNoise(rawDelta as Record<string, unknown>)
  return { rawDelta, filteredDelta }
}

export function applyPatch(
  base: Record<string, unknown>,
  delta: jsondiffpatch.Delta
): Record<string, unknown> {
  const cloned = JSON.parse(JSON.stringify(base))
  diffpatcher.patch(cloned, delta)
  return cloned
}

export { diffpatcher }
```

**Step 4: Run — pass. Commit.**

```bash
git commit -m "feat: add jsondiffpatch integration with noise filtering"
```

---

### Task 8: Semantic Translator

**Files:**
- Create: `src/lib/engine/semantic-translator.ts`
- Test: `src/__tests__/engine/semantic-translator.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { translateToSemantic } from '@/lib/engine/semantic-translator'
import { computeDiff } from '@/lib/engine/diff'
import beforeJson from '../fixtures/simple-workflow-before.json'
import afterJson from '../fixtures/simple-workflow-after.json'

describe('translateToSemantic', () => {
  it('produces a semantic changelog from two workflow JSONs', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(
      beforeJson,
      afterJson,
      filteredDelta!
    )
    expect(changelog.isEmpty).toBe(false)
    expect(changelog.groups.length).toBeGreaterThan(0)
  })

  it('detects added nodes', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta!)
    const addedGroups = changelog.groups.filter(g => g.category === 'added_node')
    expect(addedGroups.length).toBeGreaterThan(0)
    // "Add to CRM" was added in afterJson
    const crmGroup = addedGroups.find(g => g.title.includes('Add to CRM'))
    expect(crmGroup).toBeDefined()
  })

  it('detects modified node parameters', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta!)
    const modifiedGroups = changelog.groups.filter(g => g.category === 'modified_node')
    expect(modifiedGroups.length).toBeGreaterThan(0)
  })

  it('detects credential changes as security flags', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta!)
    const securityGroups = changelog.groups.filter(g => g.category === 'security')
    expect(securityGroups.length).toBeGreaterThan(0)
  })

  it('detects workflow name change', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta!)
    const settingsGroups = changelog.groups.filter(g => g.category === 'workflow_settings')
    expect(settingsGroups.length).toBeGreaterThan(0)
    expect(settingsGroups[0].changes.some(c =>
      c.description.includes('Customer Onboarding v2')
    )).toBe(true)
  })

  it('computes correct summary counts', () => {
    const { filteredDelta } = computeDiff(beforeJson, afterJson)
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta!)
    expect(changelog.summary.addedNodes).toBeGreaterThanOrEqual(1)
    expect(changelog.summary.securityFlags).toBeGreaterThanOrEqual(1)
  })

  it('returns empty changelog for identical workflows', () => {
    const changelog = translateToSemantic(beforeJson, beforeJson, null)
    expect(changelog.isEmpty).toBe(true)
    expect(changelog.groups).toHaveLength(0)
  })
})
```

**Step 2: Run — fail. Step 3: Implement.**

This is the core engine. `src/lib/engine/semantic-translator.ts` must:

1. Compare `before.nodes` and `after.nodes` by `id` to find added/removed/modified nodes
2. Compare `before.connections` and `after.connections` to find connection changes
3. Compare top-level fields (`name`, `active`, `settings`) for workflow setting changes
4. Flag credential changes on any node as security
5. Flag sticky notes as documentation changes
6. Use `getNodeDisplayName` for human-readable node types
7. Use `humanizeParameterPath` for parameter changes
8. Detect code nodes and extract code content for special rendering
9. Build `ChangeGroup[]` with proper categories
10. Compute summary counts

The implementation should be ~200-300 lines. Build it by comparing node arrays by ID, then iterating through differences.

Key implementation approach:
- Create Maps from `before.nodes` and `after.nodes` keyed by `id`
- Nodes in after but not before → added
- Nodes in before but not after → removed
- Nodes in both → deep compare parameters, credentials, disabled, etc.
- Connections: normalize and compare
- Generate unique IDs for each change/group using `crypto.randomUUID()` or counter

**Step 4: Run — pass. Commit.**

```bash
git commit -m "feat: add semantic translator — human-readable changelog from n8n diffs"
```

---

### Task 9: Security Flagger

**Files:**
- Create: `src/lib/engine/security-flagger.ts`
- Test: `src/__tests__/engine/security-flagger.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { flagSecurityChanges } from '@/lib/engine/security-flagger'
import type { SemanticChange } from '@/lib/engine/types'

describe('flagSecurityChanges', () => {
  it('flags credential changes', () => {
    const change: SemanticChange = {
      id: '1',
      category: 'modified_node',
      description: 'Changed something',
      nodeName: 'Email Node',
      details: { field: 'credentials.smtp', oldValue: 'cred-1', newValue: 'cred-2' }
    }
    const flagged = flagSecurityChanges([change])
    expect(flagged.some(c => c.category === 'security')).toBe(true)
  })

  it('flags webhook URL changes', () => {
    const change: SemanticChange = {
      id: '2',
      category: 'modified_node',
      description: 'Changed webhook path',
      nodeName: 'Webhook',
      nodeType: 'n8n-nodes-base.webhook',
      details: { field: 'parameters.path', oldValue: '/old', newValue: '/new' }
    }
    const flagged = flagSecurityChanges([change])
    expect(flagged.some(c => c.category === 'security')).toBe(true)
  })

  it('does not flag non-sensitive changes', () => {
    const change: SemanticChange = {
      id: '3',
      category: 'modified_node',
      description: 'Changed email subject',
      details: { field: 'parameters.subject', oldValue: 'old', newValue: 'new' }
    }
    const flagged = flagSecurityChanges([change])
    expect(flagged.every(c => c.category !== 'security')).toBe(true)
  })
})
```

**Step 2: Implement, test, commit.**

```bash
git commit -m "feat: add security flagger for credential and webhook changes"
```

---

### Task 10: Dependency Grouper

**Files:**
- Create: `src/lib/engine/dependency-grouper.ts`
- Test: `src/__tests__/engine/dependency-grouper.test.ts`

**Step 1: Write failing tests**

Test that when a node is added, its connections are grouped with it. When removed, its disconnections are grouped with it.

```typescript
import { describe, it, expect } from 'vitest'
import { groupDependencies } from '@/lib/engine/dependency-grouper'
import type { ChangeGroup } from '@/lib/engine/types'

describe('groupDependencies', () => {
  it('groups new connections with added nodes', () => {
    const groups: ChangeGroup[] = [
      {
        id: 'g1', category: 'added_node', title: 'Added: CRM Node',
        description: 'Added node: Add to CRM', changes: [], isAtomic: false
      },
      {
        id: 'g2', category: 'connection_change', title: 'Connected: Set Data → CRM Node',
        description: 'New connection', changes: [{
          id: 'c1', category: 'connection_change',
          description: 'Connected: Set Data → Add to CRM',
          nodeName: 'Add to CRM'
        }], isAtomic: false
      }
    ]
    const grouped = groupDependencies(groups)
    // Connection to CRM should be absorbed into the added node group
    const addedGroup = grouped.find(g => g.category === 'added_node')
    expect(addedGroup?.changes.length).toBeGreaterThan(0)
    expect(addedGroup?.isAtomic).toBe(true)
  })

  it('groups disconnections with removed nodes', () => {
    const groups: ChangeGroup[] = [
      {
        id: 'g1', category: 'removed_node', title: 'Removed: Old Node',
        description: '', changes: [], isAtomic: false
      },
      {
        id: 'g2', category: 'connection_change', title: 'Disconnected',
        description: '', changes: [{
          id: 'c1', category: 'connection_change',
          description: 'Disconnected: X → Old Node',
          nodeName: 'Old Node'
        }], isAtomic: false
      }
    ]
    const grouped = groupDependencies(groups)
    const removedGroup = grouped.find(g => g.category === 'removed_node')
    expect(removedGroup?.isAtomic).toBe(true)
  })
})
```

**Step 2: Implement, test, commit.**

```bash
git commit -m "feat: add dependency grouper for atomic node+connection bundles"
```

---

### Task 11: Selective Merge Engine

**Files:**
- Create: `src/lib/engine/merge.ts`
- Test: `src/__tests__/engine/merge.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { selectiveMerge } from '@/lib/engine/merge'
import beforeJson from '../fixtures/simple-workflow-before.json'
import afterJson from '../fixtures/simple-workflow-after.json'

describe('selectiveMerge', () => {
  it('returns after.json when all changes accepted', () => {
    const result = selectiveMerge(beforeJson, afterJson, 'all')
    // Should match after (modulo noise fields)
    expect(result.mergedJson.name).toBe(afterJson.name)
    expect((result.mergedJson.nodes as unknown[]).length).toBe(afterJson.nodes.length)
  })

  it('returns before.json when no changes accepted', () => {
    const result = selectiveMerge(beforeJson, afterJson, 'none')
    expect(result.mergedJson.name).toBe(beforeJson.name)
    expect((result.mergedJson.nodes as unknown[]).length).toBe(beforeJson.nodes.length)
  })

  it('applies only selected change groups', () => {
    // Accept only the name change, reject node additions
    const result = selectiveMerge(beforeJson, afterJson, {
      acceptedGroupIds: ['name_change'] // The semantic translator assigns IDs
    })
    expect(result.mergedJson.name).toBe(afterJson.name)
    // But node count should stay at before's count
    expect((result.mergedJson.nodes as unknown[]).length).toBe(beforeJson.nodes.length)
  })

  it('produces valid JSON output', () => {
    const result = selectiveMerge(beforeJson, afterJson, 'all')
    expect(result.valid).toBe(true)
    expect(result.warnings).toBeDefined()
  })
})
```

**Step 2: Implement the selective merge engine.**

The approach:
1. Compute full diff via jsondiffpatch
2. If 'all' → return deep clone of after
3. If 'none' → return deep clone of before
4. If partial → build merged result by applying accepted changes to before:
   - For added nodes: add them to nodes array
   - For removed nodes: remove them from nodes array
   - For modified nodes: apply parameter changes
   - For connection changes: update connections object
   - For workflow settings: apply setting changes
5. Run post-merge validation

**Step 3: Test, commit.**

```bash
git commit -m "feat: add selective merge engine with diff pruning"
```

---

### Task 12: Post-Merge Validator

**Files:**
- Create: `src/lib/engine/validator.ts`
- Test: `src/__tests__/engine/validator.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { validateMergedWorkflow } from '@/lib/engine/validator'

describe('validateMergedWorkflow', () => {
  it('passes valid workflow', () => {
    const result = validateMergedWorkflow({
      name: 'Test',
      nodes: [{ id: '1', name: 'A', type: 'test', typeVersion: 1, position: [0, 0], parameters: {} }],
      connections: {}
    })
    expect(result.valid).toBe(true)
  })

  it('detects orphan connections (target node missing)', () => {
    const result = validateMergedWorkflow({
      name: 'Test',
      nodes: [{ id: '1', name: 'A', type: 'test', typeVersion: 1, position: [0, 0], parameters: {} }],
      connections: {
        'A': { main: [[{ node: 'B', type: 'main', index: 0 }]] }
      }
    })
    expect(result.valid).toBe(false)
    expect(result.errors.some(e => e.includes('B'))).toBe(true)
  })

  it('detects orphan connections (source node missing)', () => {
    const result = validateMergedWorkflow({
      name: 'Test',
      nodes: [{ id: '1', name: 'B', type: 'test', typeVersion: 1, position: [0, 0], parameters: {} }],
      connections: {
        'A': { main: [[{ node: 'B', type: 'main', index: 0 }]] }
      }
    })
    expect(result.valid).toBe(false)
  })

  it('warns about expression references to missing nodes', () => {
    const result = validateMergedWorkflow({
      name: 'Test',
      nodes: [{
        id: '1', name: 'A', type: 'test', typeVersion: 1, position: [0, 0],
        parameters: { value: '={{ $node["MissingNode"].json.field }}' }
      }],
      connections: {}
    })
    expect(result.warnings.length).toBeGreaterThan(0)
    expect(result.warnings.some(w => w.type === 'expression_reference')).toBe(true)
  })

  it('warns about executeWorkflow references', () => {
    const result = validateMergedWorkflow({
      name: 'Test',
      nodes: [{
        id: '1', name: 'Run Sub', type: 'n8n-nodes-base.executeWorkflow',
        typeVersion: 1, position: [0, 0],
        parameters: { workflowId: 'sub-workflow-123' }
      }],
      connections: {}
    })
    expect(result.warnings.some(w => w.type === 'sub_workflow')).toBe(true)
  })
})
```

**Step 2: Implement. Validation checks per PRD Section 3.5:**
1. All connections reference existing nodes
2. All connection source names match node names
3. Required fields present
4. Expression reference validation (`$node["..."]` regex scan)
5. Sub-workflow reference detection

**Step 3: Test, commit.**

```bash
git commit -m "feat: add post-merge validator with expression and connection checks"
```

---

### Task 13: Prisma Schema + Database

**Files:**
- Create: `prisma/schema.prisma`
- Create: `src/lib/db.ts`

**Step 1: Initialize Prisma**

```bash
npx prisma init
```

**Step 2: Write schema matching PRD Section 5**

`prisma/schema.prisma`:
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DIRECT_URL")
}

model Instance {
  id              String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId          String   @map("user_id") @db.Uuid
  name            String
  url             String
  encryptedApiKey String   @map("encrypted_api_key")
  status          String   @default("connected")
  lastVerifiedAt  DateTime? @map("last_verified_at")
  createdAt       DateTime @default(now()) @map("created_at")
  updatedAt       DateTime @updatedAt @map("updated_at")

  comparisons Comparison[]

  @@index([userId], name: "idx_instances_user")
  @@map("instances")
}

model Comparison {
  id                    String    @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  userId                String    @map("user_id") @db.Uuid
  instanceId            String?   @map("instance_id") @db.Uuid
  workflowId            String?   @map("workflow_id")
  workflowName          String    @map("workflow_name")
  description           String?
  beforeJson            Json      @map("before_json")
  status                String    @default("draft")
  reviewToken           String?   @unique @map("review_token")
  reviewTokenExpiresAt  DateTime? @map("review_token_expires_at")
  pushMode              String?   @map("push_mode")
  pushResult            Json?     @map("push_result")
  pushedAt              DateTime? @map("pushed_at")
  createdAt             DateTime  @default(now()) @map("created_at")
  updatedAt             DateTime  @updatedAt @map("updated_at")

  instance  Instance?           @relation(fields: [instanceId], references: [id])
  revisions ComparisonRevision[]
  comments  Comment[]

  @@index([userId], name: "idx_comparisons_user")
  @@index([instanceId], name: "idx_comparisons_instance")
  @@index([status], name: "idx_comparisons_status")
  @@index([reviewToken], name: "idx_comparisons_token")
  @@map("comparisons")
}

model ComparisonRevision {
  id                String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  comparisonId      String   @map("comparison_id") @db.Uuid
  revisionNumber    Int      @default(1) @map("revision_number")
  afterJson         Json     @map("after_json")
  diffResult        Json     @map("diff_result")
  semanticChangelog Json     @map("semantic_changelog")
  mergedJson        Json?    @map("merged_json")
  createdAt         DateTime @default(now()) @map("created_at")

  comparison      Comparison        @relation(fields: [comparisonId], references: [id], onDelete: Cascade)
  changeSelections ChangeSelection[]

  @@unique([comparisonId, revisionNumber])
  @@index([comparisonId], name: "idx_revisions_comparison")
  @@map("comparison_revisions")
}

model Comment {
  id              String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  comparisonId    String   @map("comparison_id") @db.Uuid
  revisionNumber  Int      @default(1) @map("revision_number")
  changeGroupId   String?  @map("change_group_id")
  authorName      String   @map("author_name")
  authorRole      String   @map("author_role")
  content         String
  createdAt       DateTime @default(now()) @map("created_at")

  comparison Comparison @relation(fields: [comparisonId], references: [id], onDelete: Cascade)

  @@index([comparisonId], name: "idx_comments_comparison")
  @@map("comments")
}

model ChangeSelection {
  id             String   @id @default(dbgenerated("gen_random_uuid()")) @db.Uuid
  revisionId     String   @map("revision_id") @db.Uuid
  changeGroupId  String   @map("change_group_id")
  accepted       Boolean  @default(true)
  selectedAt     DateTime @default(now()) @map("selected_at")

  revision ComparisonRevision @relation(fields: [revisionId], references: [id], onDelete: Cascade)

  @@index([revisionId], name: "idx_selections_revision")
  @@map("change_selections")
}
```

**Step 3: Create Prisma client singleton**

`src/lib/db.ts`:
```typescript
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma = globalForPrisma.prisma || new PrismaClient()

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
```

**Step 4: Generate Prisma client (no migration yet — needs Supabase)**

```bash
npx prisma generate
```

**Step 5: Commit**

```bash
git commit -m "feat: add Prisma schema matching PRD database design"
```

---

### Task 14: AES-256-GCM Encryption Utility

**Files:**
- Create: `src/lib/crypto.ts`
- Test: `src/__tests__/crypto.test.ts`

**Step 1: Write failing tests**

```typescript
import { describe, it, expect } from 'vitest'
import { encrypt, decrypt } from '@/lib/crypto'

describe('crypto', () => {
  it('encrypts and decrypts a string correctly', () => {
    const original = 'n8n-api-key-abc123'
    const encrypted = encrypt(original)
    expect(encrypted).not.toBe(original)
    expect(decrypt(encrypted)).toBe(original)
  })

  it('produces different ciphertexts for same input (random IV)', () => {
    const input = 'same-key'
    const e1 = encrypt(input)
    const e2 = encrypt(input)
    expect(e1).not.toBe(e2) // Different IVs
  })

  it('throws on tampered ciphertext', () => {
    const encrypted = encrypt('test')
    const tampered = encrypted.slice(0, -4) + 'xxxx'
    expect(() => decrypt(tampered)).toThrow()
  })
})
```

**Step 2: Implement**

`src/lib/crypto.ts`:
```typescript
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'

const ALGORITHM = 'aes-256-gcm'
const IV_LENGTH = 16
const TAG_LENGTH = 16

function getKey(): Buffer {
  const key = process.env.ENCRYPTION_KEY
  if (!key) throw new Error('ENCRYPTION_KEY not set')
  return Buffer.from(key, 'hex')
}

export function encrypt(plaintext: string): string {
  const iv = randomBytes(IV_LENGTH)
  const cipher = createCipheriv(ALGORITHM, getKey(), iv)
  const encrypted = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return Buffer.concat([iv, tag, encrypted]).toString('base64')
}

export function decrypt(ciphertext: string): string {
  const buf = Buffer.from(ciphertext, 'base64')
  const iv = buf.subarray(0, IV_LENGTH)
  const tag = buf.subarray(IV_LENGTH, IV_LENGTH + TAG_LENGTH)
  const encrypted = buf.subarray(IV_LENGTH + TAG_LENGTH)
  const decipher = createDecipheriv(ALGORITHM, getKey(), iv)
  decipher.setAuthTag(tag)
  return decipher.update(encrypted) + decipher.final('utf8')
}
```

Note: Tests need `ENCRYPTION_KEY` env var. Add to test setup:
```typescript
// In test setup or vitest.config.ts env
process.env.ENCRYPTION_KEY = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
```

**Step 3: Test, commit.**

```bash
git commit -m "feat: add AES-256-GCM encryption for API key storage"
```

---

### Task 15: JSON Upload UI Component

**Files:**
- Create: `src/components/upload/json-dropzone.tsx`
- Create: `src/components/upload/upload-form.tsx`

**Step 1: Implement the dropzone component**

`src/components/upload/json-dropzone.tsx`:
```tsx
'use client'

import { useCallback, useState } from 'react'
import { useDropzone } from 'react-dropzone'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { validateN8nWorkflow } from '@/lib/n8n/validation'

interface JsonDropzoneProps {
  label: string
  onFileAccepted: (json: Record<string, unknown>, filename: string) => void
  onError: (message: string) => void
}

export function JsonDropzone({ label, onFileAccepted, onError }: JsonDropzoneProps) {
  const [filename, setFilename] = useState<string | null>(null)
  const [valid, setValid] = useState<boolean | null>(null)

  const onDrop = useCallback((acceptedFiles: File[]) => {
    const file = acceptedFiles[0]
    if (!file) return

    if (file.size > 10 * 1024 * 1024) {
      onError('File exceeds 10MB limit.')
      return
    }

    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const json = JSON.parse(e.target?.result as string)
        const validation = validateN8nWorkflow(json)
        if (!validation.valid) {
          setValid(false)
          onError(`Invalid n8n workflow JSON: ${validation.errors[0]}`)
          return
        }
        setFilename(file.name)
        setValid(true)
        onFileAccepted(json, file.name)
      } catch {
        setValid(false)
        onError("This file isn't valid JSON.")
      }
    }
    reader.readAsText(file)
  }, [onFileAccepted, onError])

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'application/json': ['.json'] },
    maxFiles: 1,
  })

  return (
    <Card
      {...getRootProps()}
      className={`cursor-pointer border-2 border-dashed transition-colors ${
        isDragActive ? 'border-primary bg-primary/5' : 'border-muted-foreground/25'
      } ${valid === true ? 'border-green-500' : ''} ${valid === false ? 'border-red-500' : ''}`}
    >
      <CardContent className="flex flex-col items-center justify-center p-8 text-center">
        <input {...getInputProps()} />
        <p className="text-sm font-medium">{label}</p>
        {filename ? (
          <Badge variant={valid ? 'default' : 'destructive'} className="mt-2">
            {filename}
          </Badge>
        ) : (
          <p className="text-xs text-muted-foreground mt-1">
            Drag & drop .json file or click to browse
          </p>
        )}
      </CardContent>
    </Card>
  )
}
```

**Step 2: Implement the upload form**

`src/components/upload/upload-form.tsx`:
```tsx
'use client'

import { useState } from 'react'
import { JsonDropzone } from './json-dropzone'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Alert, AlertDescription } from '@/components/ui/alert'

interface UploadFormProps {
  onCompare: (data: {
    beforeJson: Record<string, unknown>
    afterJson: Record<string, unknown>
    description: string
  }) => void
}

export function UploadForm({ onCompare }: UploadFormProps) {
  const [beforeJson, setBeforeJson] = useState<Record<string, unknown> | null>(null)
  const [afterJson, setAfterJson] = useState<Record<string, unknown> | null>(null)
  const [description, setDescription] = useState('')
  const [error, setError] = useState<string | null>(null)

  const canCompare = beforeJson && afterJson

  return (
    <div className="space-y-6">
      {error && (
        <Alert variant="destructive">
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label className="mb-2 block">Before (Original)</Label>
          <JsonDropzone
            label="Drop original workflow JSON"
            onFileAccepted={(json) => { setBeforeJson(json); setError(null) }}
            onError={setError}
          />
        </div>
        <div>
          <Label className="mb-2 block">After (Modified)</Label>
          <JsonDropzone
            label="Drop modified workflow JSON"
            onFileAccepted={(json) => { setAfterJson(json); setError(null) }}
            onError={setError}
          />
        </div>
      </div>

      <div>
        <Label htmlFor="description" className="mb-2 block">
          Description (like a commit message)
        </Label>
        <Textarea
          id="description"
          placeholder="e.g., Added invoice validation step"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={2}
        />
      </div>

      <Button
        onClick={() => onCompare({ beforeJson: beforeJson!, afterJson: afterJson!, description })}
        disabled={!canCompare}
        className="w-full"
        size="lg"
      >
        Compare Workflows
      </Button>
    </div>
  )
}
```

**Step 3: Commit**

```bash
git commit -m "feat: add JSON upload dropzone with validation"
```

---

### Task 16: Comparison API Route — Create

**Files:**
- Create: `src/app/api/comparisons/route.ts`

**Step 1: Implement POST /api/comparisons**

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/db'
import { validateN8nWorkflow } from '@/lib/n8n/validation'
import { computeDiff } from '@/lib/engine/diff'
import { translateToSemantic } from '@/lib/engine/semantic-translator'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { beforeJson, afterJson, description, workflowName, instanceId, workflowId } = body

    // Validate both JSONs
    const beforeValidation = validateN8nWorkflow(beforeJson)
    if (!beforeValidation.valid) {
      return NextResponse.json(
        { error: `Invalid before JSON: ${beforeValidation.errors[0]}` },
        { status: 400 }
      )
    }

    const afterValidation = validateN8nWorkflow(afterJson)
    if (!afterValidation.valid) {
      return NextResponse.json(
        { error: `Invalid after JSON: ${afterValidation.errors[0]}` },
        { status: 400 }
      )
    }

    // Compute diff
    const { rawDelta, filteredDelta } = computeDiff(beforeJson, afterJson)

    // Translate to semantic changelog
    const changelog = translateToSemantic(beforeJson, afterJson, filteredDelta)

    // TODO: Get userId from Supabase auth session
    const userId = '00000000-0000-0000-0000-000000000000' // Placeholder

    // Create comparison + first revision in transaction
    const comparison = await prisma.comparison.create({
      data: {
        userId,
        instanceId: instanceId || null,
        workflowId: workflowId || null,
        workflowName: workflowName || beforeJson.name as string || 'Untitled Workflow',
        description: description || null,
        beforeJson: beforeJson,
        status: 'draft',
        revisions: {
          create: {
            revisionNumber: 1,
            afterJson: afterJson,
            diffResult: rawDelta || {},
            semanticChangelog: changelog as unknown as Record<string, unknown>,
          }
        }
      },
      include: { revisions: true }
    })

    return NextResponse.json(comparison, { status: 201 })
  } catch (error) {
    console.error('Create comparison error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const status = searchParams.get('status')
    const instanceId = searchParams.get('instanceId')

    // TODO: Get userId from session
    const userId = '00000000-0000-0000-0000-000000000000'

    const comparisons = await prisma.comparison.findMany({
      where: {
        userId,
        ...(status && { status }),
        ...(instanceId && { instanceId }),
      },
      include: {
        revisions: {
          orderBy: { revisionNumber: 'desc' },
          take: 1,
        },
        instance: true,
      },
      orderBy: { createdAt: 'desc' },
    })

    return NextResponse.json(comparisons)
  } catch (error) {
    console.error('List comparisons error:', error)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
}
```

**Step 2: Commit**

```bash
git commit -m "feat: add comparison creation API route with diff computation"
```

---

### Task 17: Changelog Display Components

**Files:**
- Create: `src/components/changelog/change-card.tsx`
- Create: `src/components/changelog/category-section.tsx`
- Create: `src/components/changelog/changelog-list.tsx`
- Create: `src/components/changelog/summary-bar.tsx`
- Create: `src/components/changelog/code-diff-viewer.tsx`

**Step 1: Implement change-card (single change with checkbox + expand)**

`src/components/changelog/change-card.tsx` — Shows one change with:
- Checkbox (developer mode) or read-only (client mode)
- Category badge with color
- Human-readable description
- "See details" expander → raw JSON diff or code diff
- For code nodes: side-by-side diff via react-diff-viewer-continued

**Step 2: Implement category-section (groups changes by category)**

Renders changes in PRD display order:
1. Security Flags (orange)
2. Added Nodes (green)
3. Removed Nodes (red)
4. Modified Nodes (amber)
5. Connection Changes (blue)
6. Workflow Settings (gray)
7. Documentation Changes (muted)

**Step 3: Implement summary-bar**

"X nodes added, Y modified, Z connections changed" with colored counts.

**Step 4: Implement code-diff-viewer wrapper**

```tsx
'use client'

import dynamic from 'next/dynamic'

const ReactDiffViewer = dynamic(
  () => import('react-diff-viewer-continued'),
  { ssr: false }
)

interface CodeDiffViewerProps {
  oldCode: string
  newCode: string
  language: 'javascript' | 'python'
}

export function CodeDiffViewer({ oldCode, newCode, language }: CodeDiffViewerProps) {
  return (
    <div className="rounded-md overflow-hidden border">
      <div className="bg-muted px-3 py-1 text-xs font-medium">{language}</div>
      <ReactDiffViewer
        oldValue={oldCode}
        newValue={newCode}
        splitView={true}
        useDarkTheme={false}
        showDiffOnly={true}
        extraLinesSurroundingDiff={3}
        leftTitle="Before"
        rightTitle="After"
      />
    </div>
  )
}
```

**Step 5: Implement changelog-list (orchestrator)**

Composes summary-bar + category-sections. Accepts `mode: 'developer' | 'client'` to toggle checkboxes.

**Step 6: Commit**

```bash
git commit -m "feat: add changelog display components with code diff support"
```

---

### Task 18: Developer Review Page + New Comparison Page

**Files:**
- Create: `src/app/(dashboard)/compare/new/page.tsx`
- Create: `src/app/(dashboard)/compare/[id]/page.tsx`
- Create: `src/app/(dashboard)/compare/[id]/finalize/page.tsx`
- Create: `src/store/comparison-store.ts`

**Step 1: Implement Zustand store**

`src/store/comparison-store.ts`:
```typescript
import { create } from 'zustand'
import type { SemanticChangelog, ChangeGroup } from '@/lib/engine/types'

interface ComparisonStore {
  changelog: SemanticChangelog | null
  selections: Record<string, boolean> // groupId → accepted
  setChangelog: (changelog: SemanticChangelog) => void
  toggleSelection: (groupId: string) => void
  acceptAll: () => void
  rejectAll: () => void
  getAcceptedGroupIds: () => string[]
}

export const useComparisonStore = create<ComparisonStore>((set, get) => ({
  changelog: null,
  selections: {},

  setChangelog: (changelog) => {
    const selections: Record<string, boolean> = {}
    changelog.groups.forEach(g => { selections[g.id] = true }) // Default: accept all
    set({ changelog, selections })
  },

  toggleSelection: (groupId) => set((state) => ({
    selections: { ...state.selections, [groupId]: !state.selections[groupId] }
  })),

  acceptAll: () => set((state) => {
    const selections: Record<string, boolean> = {}
    state.changelog?.groups.forEach(g => { selections[g.id] = true })
    return { selections }
  }),

  rejectAll: () => set((state) => {
    const selections: Record<string, boolean> = {}
    state.changelog?.groups.forEach(g => { selections[g.id] = false })
    return { selections }
  }),

  getAcceptedGroupIds: () => {
    const state = get()
    return Object.entries(state.selections)
      .filter(([, v]) => v)
      .map(([k]) => k)
  },
}))
```

**Step 2: Implement new comparison page**

`src/app/(dashboard)/compare/new/page.tsx`:
- Renders `UploadForm`
- On submit: POST to `/api/comparisons`
- On success: redirect to `/compare/[id]`

**Step 3: Implement review page**

`src/app/(dashboard)/compare/[id]/page.tsx`:
- Fetch comparison + latest revision from API
- Render `ChangelogList` in developer mode (with checkboxes)
- "Accept All" / "Reject All" buttons
- "Share with Client" button
- "Finalize" button → navigate to `/compare/[id]/finalize`

**Step 4: Implement finalize page**

`src/app/(dashboard)/compare/[id]/finalize/page.tsx`:
- Summary of accepted/rejected changes
- Validation warnings (from post-merge validator)
- "Download Merged JSON" button (always available)
- If connected instance: push mode selector + "Push" button (Phase 3)

**Step 5: Commit**

```bash
git commit -m "feat: add comparison pages — new, review, and finalize"
```

---

## Phase 2: Client Review + Comments (Tasks 19–25)

### Task 19: Review Token Generation + Share API

**Files:**
- Create: `src/app/api/comparisons/[id]/share/route.ts`

**Step 1: Implement share endpoint**

Generates UUID v4 token, stores in comparison, returns shareable URL.
Token expires in 30 days.

```typescript
import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/db'
import { v4 as uuidv4 } from 'uuid'

export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  const token = uuidv4()
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)

  const comparison = await prisma.comparison.update({
    where: { id: params.id },
    data: {
      reviewToken: token,
      reviewTokenExpiresAt: expiresAt,
      status: 'pending_review',
    },
  })

  const reviewUrl = `${process.env.NEXT_PUBLIC_APP_URL}/review/${token}`
  return NextResponse.json({ reviewUrl, token, expiresAt })
}
```

**Step 2: Commit**

```bash
git commit -m "feat: add review token generation for client sharing"
```

---

### Task 20: Client Review API (token-based, no auth)

**Files:**
- Create: `src/app/api/review/[token]/route.ts`
- Create: `src/app/api/review/[token]/comment/route.ts`
- Create: `src/app/api/review/[token]/approve/route.ts`
- Create: `src/app/api/review/[token]/request-changes/route.ts`

**Step 1: Implement GET /api/review/:token**

Fetch comparison by token, validate not expired, return comparison + latest revision changelog.

**Step 2: Implement POST /api/review/:token/comment**

Accept `{ authorName, content, changeGroupId? }`. Create comment.

**Step 3: Implement POST /api/review/:token/approve**

Update comparison status to 'approved'.

**Step 4: Implement POST /api/review/:token/request-changes**

Requires at least one comment. Update status to 'changes_requested'.

**Step 5: Commit**

```bash
git commit -m "feat: add client review API — comments, approve, request changes"
```

---

### Task 21: Client Review Page (Public)

**Files:**
- Create: `src/app/review/[token]/page.tsx`
- Create: `src/components/review/name-entry.tsx`
- Create: `src/components/review/comment-thread.tsx`
- Create: `src/components/review/review-actions.tsx`

**Step 1: Implement name entry**

First visit shows: "You're reviewing changes to {workflow}. Your name:"
Store in localStorage.

**Step 2: Implement read-only changelog**

Same `ChangelogList` component but with `mode="client"` (no checkboxes).

**Step 3: Implement comment threads**

Per-change comments + global comment thread.
Author name auto-filled from localStorage.

**Step 4: Implement review actions**

"Approve All" button — calls approve API.
"Request Changes" button — requires at least one comment, calls request-changes API.

**Step 5: Mobile-responsive from day one**

- Cards stack vertically on mobile
- Comment threads collapse
- Approve/reject buttons full-width and thumb-friendly
- Use Tailwind responsive classes: `grid-cols-1 md:grid-cols-2`

**Step 6: Commit**

```bash
git commit -m "feat: add client review page — read-only, comments, mobile-responsive"
```

---

### Task 22: Comment System Backend

**Files:**
- Modify: `src/app/api/comparisons/[id]/route.ts` (add comment fetching)

**Step 1: Wire up comment creation + retrieval**

Comments are created via both the client review API (`/api/review/:token/comment`) and the developer dashboard. Both write to the same `comments` table. Comments include `revisionNumber` to track which revision they were made on.

**Step 2: Commit**

```bash
git commit -m "feat: complete comment system — per-change and global threads"
```

---

### Task 23: Revision System

**Files:**
- Create: `src/app/api/comparisons/[id]/revisions/route.ts`

**Step 1: Implement POST — new revision**

When developer uploads a new "after" JSON on the same comparison:
1. Increment revision_number
2. Re-diff against original before_json
3. Store new semantic changelog
4. Preserve existing comments

**Step 2: Implement GET — list revisions**

Return all revisions for a comparison, ordered by revision_number.

**Step 3: Add "New in revision N" badges to changelog display**

Compare current revision's changelog with previous to identify new changes.

**Step 4: Commit**

```bash
git commit -m "feat: add revision system — new after uploads re-diff against baseline"
```

---

### Task 24: Comparison Status Management

**Files:**
- Modify: `src/app/api/comparisons/[id]/route.ts`

**Step 1: Implement PATCH for status transitions**

Valid transitions:
- `draft` → `pending_review` (when share link generated)
- `pending_review` → `approved` (when client approves)
- `pending_review` → `changes_requested` (when client requests changes)
- `changes_requested` → `pending_review` (when new revision uploaded)
- `approved` → `merged` (when merge executed)
- `merged` → `pushed` (when pushed to n8n)

**Step 2: Commit**

```bash
git commit -m "feat: add comparison status state machine"
```

---

### Task 25: Developer Dashboard

**Files:**
- Create: `src/app/(dashboard)/page.tsx`
- Create: `src/components/layout/sidebar.tsx`
- Create: `src/components/layout/header.tsx`
- Create: `src/app/(dashboard)/layout.tsx`

**Step 1: Implement dashboard layout**

Sidebar with nav: Dashboard, Instances, New Comparison.
Header with user info (placeholder until auth).

**Step 2: Implement dashboard page**

- List all comparisons with status badges
- Filter by status, instance
- Search by workflow name
- Each comparison card shows: workflow name, description, status, date, instance
- Click → navigate to `/compare/[id]`

**Step 3: Commit**

```bash
git commit -m "feat: add developer dashboard with comparison list and filtering"
```

---

## Phase 3: n8n Instance Connection + Push (Tasks 26–33)

### Task 26: Instance Management API

**Files:**
- Create: `src/app/api/instances/route.ts`
- Create: `src/app/api/instances/[id]/route.ts`
- Create: `src/app/api/instances/[id]/verify/route.ts`
- Create: `src/app/api/instances/[id]/workflows/route.ts`

**Step 1: Implement CRUD**

POST (create) — encrypt API key with AES-256-GCM, test connection.
GET (list) — return all instances for user.
PATCH (update) — re-encrypt if API key changed.
DELETE — cascade delete.

**Step 2: Implement /verify**

POST — call `GET /api/v1/workflows` on the n8n instance. Return success/failure.

**Step 3: Implement /workflows**

GET — proxy call to n8n instance's `GET /api/v1/workflows`. Return list.

**Step 4: Commit**

```bash
git commit -m "feat: add instance management API with encryption and proxy"
```

---

### Task 27: n8n API Client

**Files:**
- Create: `src/lib/n8n/api-client.ts`

**Step 1: Implement n8n REST API wrapper**

```typescript
import { decrypt } from '@/lib/crypto'

interface N8nClientConfig {
  url: string
  encryptedApiKey: string
}

export class N8nApiClient {
  private baseUrl: string
  private apiKey: string

  constructor(config: N8nClientConfig) {
    this.baseUrl = config.url.replace(/\/$/, '')
    this.apiKey = decrypt(config.encryptedApiKey)
  }

  private async fetch(path: string, options: RequestInit = {}) {
    const response = await fetch(`${this.baseUrl}/api/v1${path}`, {
      ...options,
      headers: {
        'X-N8N-API-KEY': this.apiKey,
        'Content-Type': 'application/json',
        ...options.headers,
      },
      signal: AbortSignal.timeout(10000),
    })

    if (!response.ok) {
      throw new Error(`n8n API error: ${response.status} ${response.statusText}`)
    }

    return response.json()
  }

  async listWorkflows() { return this.fetch('/workflows') }
  async getWorkflow(id: string) { return this.fetch(`/workflows/${id}`) }
  async createWorkflow(data: unknown) {
    return this.fetch('/workflows', { method: 'POST', body: JSON.stringify(data) })
  }
  async updateWorkflow(id: string, data: unknown) {
    return this.fetch(`/workflows/${id}`, { method: 'PATCH', body: JSON.stringify(data) })
  }
  async activateWorkflow(id: string) {
    return this.fetch(`/workflows/${id}/activate`, { method: 'POST' })
  }
  async deactivateWorkflow(id: string) {
    return this.fetch(`/workflows/${id}/deactivate`, { method: 'POST' })
  }
  async listCredentials() { return this.fetch('/credentials') }
}
```

**Step 2: Commit**

```bash
git commit -m "feat: add n8n API client with encrypted key decryption"
```

---

### Task 28: Instance Management UI

**Files:**
- Create: `src/app/(dashboard)/instances/page.tsx`
- Create: `src/app/(dashboard)/instances/new/page.tsx`
- Create: `src/components/instances/instance-card.tsx`
- Create: `src/components/instances/instance-form.tsx`

**Step 1: Instance list page** — cards showing name, URL, status, last verified.
**Step 2: New instance form** — name, URL, API key fields. Verify on submit.
**Step 3: Commit**

```bash
git commit -m "feat: add instance management UI — list, connect, verify"
```

---

### Task 29: Workflow Picker (Connected Instance Flow)

**Files:**
- Modify: `src/components/upload/upload-form.tsx` — add connected instance tab
- Modify: `src/app/(dashboard)/compare/new/page.tsx` — add workflow selection

**Step 1: Add tabs to new comparison page**

Tab 1: JSON Upload (existing)
Tab 2: Connected Instance — select instance, select workflow, auto-fetch "before"

**Step 2: Implement workflow dropdown**

Fetch workflows from selected instance via `/api/instances/:id/workflows`.
On selection, fetch the full workflow JSON as "before".
User still uploads "after" JSON.

**Step 3: Commit**

```bash
git commit -m "feat: add workflow picker for connected instance comparison flow"
```

---

### Task 30: Push Engine

**Files:**
- Create: `src/lib/engine/push.ts`
- Create: `src/app/api/comparisons/[id]/push/route.ts`
- Test: `src/__tests__/engine/push.test.ts`

**Step 1: Implement push modes**

Three modes per PRD:
1. **Push as duplicate** — `POST /workflows` with modified name
2. **Deactivate → Push** — Deactivate, PATCH, leave deactivated
3. **Direct push** — PATCH directly

**Step 2: Pre-push safety checks**

- Instance connection alive
- Target workflow still exists
- Stale state detection (compare live vs stored before)
- Active workflow warning

**Step 3: Push failure recovery**

For deactivate-push mode: if PATCH fails, auto-reactivate the original.

**Step 4: Commit**

```bash
git commit -m "feat: add push engine with 3 modes and safety checks"
```

---

### Task 31: Credential Mapping UI

**Files:**
- Create: `src/components/finalize/credential-mapper.tsx`
- Modify: `src/app/(dashboard)/compare/[id]/finalize/page.tsx`

**Step 1: Detect credential mismatches**

Compare credentials in merged JSON against available credentials on target instance.

**Step 2: Build mapping UI**

For each mismatched credential: dropdown to select matching credential on target.

**Step 3: Replace credential IDs in merged JSON before push**

**Step 4: Commit**

```bash
git commit -m "feat: add credential mapping UI for push flow"
```

---

### Task 32: Webhook URL Preservation

**Files:**
- Modify: `src/lib/engine/push.ts`
- Create: `src/components/finalize/webhook-resolver.tsx`

**Step 1: Detect webhook nodes with different paths**

Compare webhook paths in merged JSON vs target instance.

**Step 2: Show warning with option to preserve target path**

**Step 3: Commit**

```bash
git commit -m "feat: add webhook URL preservation detection on push"
```

---

### Task 33: Finalize Page — Complete Push/Download Flow

**Files:**
- Modify: `src/app/(dashboard)/compare/[id]/finalize/page.tsx`

**Step 1: Wire up all finalize components**

- Merge summary
- Validation warnings
- Push mode selector (if connected)
- Credential mapper (if needed)
- Webhook resolver (if needed)
- "Push" button (calls `/api/comparisons/:id/push`)
- "Download Merged JSON" button (always available)
- Post-push success screen

**Step 2: Implement download**

```typescript
function downloadJson(data: Record<string, unknown>, filename: string) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
```

**Step 3: Commit**

```bash
git commit -m "feat: complete finalize page — push, download, credential mapping"
```

---

## Phase 4: Polish + Production Hardening (Tasks 34–38)

### Task 34: Dashboard Polish

**Files:**
- Modify: `src/app/(dashboard)/page.tsx`

**Step 1: Add filtering by instance, status, date range**
**Step 2: Add search by workflow name**
**Step 3: Add status badges with proper colors**
**Step 4: Commit**

```bash
git commit -m "feat: polish dashboard — filters, search, status badges"
```

---

### Task 35: Error Handling Matrix

**Files:**
- Create: `src/lib/errors.ts`
- Modify: All API routes — add error handling per PRD Section 8

**Step 1: Create error classes**

Map every scenario from PRD error table to specific error types with user-facing messages.

**Step 2: Add error boundaries to all pages**

**Step 3: Add toast notifications for user actions**

```bash
npx shadcn@latest add sonner
```

Use `toast()` for success/error feedback on all actions.

**Step 4: Commit**

```bash
git commit -m "feat: add comprehensive error handling with user-facing messages"
```

---

### Task 36: Supabase Auth Integration

**Files:**
- Install: `@supabase/supabase-js`, `@supabase/ssr`
- Create: `src/lib/supabase/server.ts`
- Create: `src/lib/supabase/client.ts`
- Create: `src/lib/supabase/middleware.ts`
- Create: `src/middleware.ts`
- Create: `src/app/login/page.tsx`

**Step 1: Set up Supabase auth**

```bash
npm install @supabase/supabase-js @supabase/ssr
```

**Step 2: Implement server-side client**

```typescript
import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'

export function createClient() {
  const cookieStore = cookies()
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) { return cookieStore.get(name)?.value },
        set(name: string, value: string, options: CookieOptions) {
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          cookieStore.set({ name, value: '', ...options })
        },
      },
    }
  )
}
```

**Step 3: Add middleware for route protection**

All `/(dashboard)` routes require auth. `/review/[token]` is public.

**Step 4: Implement login page**

Email/password login via Supabase Auth.

**Step 5: Replace placeholder userId in all API routes with actual auth**

**Step 6: Commit**

```bash
git commit -m "feat: add Supabase auth — login, middleware, session management"
```

---

### Task 37: UI Polish

**Files:**
- Add loading states to all pages
- Add skeleton screens for data loading
- Add proper empty states
- Add transitions/animations where appropriate

**Step 1: Loading states**

Every page that fetches data shows a skeleton while loading.

**Step 2: Empty states**

- No comparisons: "No comparisons yet. Create your first comparison to get started."
- No instances: "No instances connected. Connect an n8n instance to pull workflows directly."
- No changes detected: "No functional changes detected. The workflows are identical."

**Step 3: Add sonner toast notifications for all user actions**

**Step 4: Commit**

```bash
git commit -m "feat: UI polish — loading states, skeletons, empty states, toasts"
```

---

### Task 38: Deployment

**Files:**
- Create: `vercel.json` (if needed)
- Update: `.env.example` with all production vars

**Step 1: Set up Supabase production project**

- Create new Supabase project
- Run Prisma migrations: `npx prisma migrate deploy`
- Set up RLS policies (Row Level Security)

**Step 2: Deploy to Vercel**

```bash
npx vercel
```

Set environment variables:
- `DATABASE_URL` (pooled)
- `DIRECT_URL` (direct)
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ENCRYPTION_KEY`
- `NEXT_PUBLIC_APP_URL`

**Step 3: Verify production**

- Upload flow works
- Review link works
- Push to n8n works
- Mobile responsive

**Step 4: Commit**

```bash
git commit -m "feat: production deployment configuration"
```

---

## Execution Notes

### Key Dependencies Between Tasks

```
Task 1 (scaffold) → everything
Task 2 (types) → Tasks 3-12 (all engine)
Task 6 (engine types) → Tasks 7-12
Task 7 (diff) → Task 8 (semantic) → Task 9 (security) → Task 10 (grouper)
Task 11 (merge) depends on Task 7 + 12 (validator)
Task 13 (prisma) → Tasks 16, 19-24 (all API routes)
Task 14 (crypto) → Task 26 (instance management)
Tasks 15-18 (UI) depend on Tasks 2-12 (engine)
Phase 2 depends on Phase 1
Phase 3 depends on Phase 2 (for status management)
Phase 4 depends on Phases 1-3
```

### Parallelizable Tasks

Within Phase 1:
- Tasks 3, 4, 5 (registry, humanizer, noise filter) are independent
- Task 6 (types) is independent
- Task 14 (crypto) is independent of engine tasks
- Task 13 (prisma) is independent of engine tasks

### Test Strategy

- **Unit tests**: All engine code (Tasks 3-12) — pure functions, easy to test
- **Integration tests**: API routes (Tasks 16, 19-24, 26-33) — test with Prisma mock or test DB
- **E2E**: Manual testing of full flow after each phase

### Critical Implementation Notes

1. **Prisma 6.x**: Do NOT upgrade to Prisma 7.x — breaking change with Supabase `directUrl`
2. **jsondiffpatch objectHash**: Must use `obj.id` for node identity matching
3. **react-diff-viewer SSR**: Must use `dynamic(() => import(...), { ssr: false })` — it uses `window`
4. **Supabase connection pooling**: Use `?pgbouncer=true&connection_limit=1` for serverless
5. **n8n connections keyed by name**: If a node is renamed, its connection key changes — handle this in the semantic translator
