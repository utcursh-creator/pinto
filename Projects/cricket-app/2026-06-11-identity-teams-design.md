---
type: spec
date: 2026-06-11
project: cricket-app
sub-project: identity-and-teams
status: draft
tags: [cricket-app, spec, auth, teams, flutter, supabase]
---

# Cricket App - Sub-project #1: Identity & Teams (Design Spec)

## Project context (the whole thing)

A CricHeroes-style cricket app for iOS + Android. The product is **scoring + profiles (C)** as the content engine and a **ranked social feed (B)** as the layer on top. Matchmaking ("find a team to play nearby") is explicitly **out of scope for v1**.

- **Builder:** solo, with AI assistance. No team, no budget. This constraint drives every choice toward one cross-platform codebase + managed backend.
- **Stack (locked):**
  - **Mobile:** Flutter (Dart, single codebase → iOS + Android)
  - **Backend:** Supabase - Postgres + Auth + Realtime + Storage
  - **Scoring (later sub-project):** online-required, live broadcast via Supabase Realtime
  - **Push:** FCM / APNs (via Supabase / Firebase)
- **Connectivity stance:** always-on baseline (no offline-first, no sync engine). Only standard write robustness: optimistic UI + silent retry on a single failed request. No buffering a whole match, no sync queue.

### Decomposition (each gets its own spec → plan → build cycle)

1. **Identity & Teams** ← *this spec* - phone-OTP auth, player profiles, teams, guest players
2. **Scoring Core** - ball-by-ball engine, live broadcast (the hard one, the content engine)
3. **Stats & Rankings** - derive batting/bowling stats, career profiles, leaderboards from scored matches
4. **Social Graph** - follow/unfollow, posts (incl. auto-generated match posts), likes, comments
5. **Feed & Ranking** - chronological → engagement-ranked → personalized (the edge over CricHeroes)
6. **Notifications & polish**

Build order: 1 → 2 → 3 → 4 → 5 → 6. App is demoable after #3, social after #5.

---

## This sub-project: purpose

Establish **who a user is** and **what teams exist**, so that every later sub-project (a scored match, a stat, a post) can attach to a real player and a real team. Nothing in #2–#6 can be built until identity + teams exist.

### Success criteria

A new user can: install → sign in with Google/Apple → create a player profile → create a team (becoming its captain) → add players to that team (real users via invite/search, **or guest players who aren't on the app yet**) → and a guest player can later sign in and **claim** their profile, inheriting their history.

---

## 1. Authentication

**Method: Google + Apple social login via Supabase Auth (native OAuth providers). No phone-OTP, no SMS in v1.**

- **Google Sign-In** is the primary path. On Android the Google account is already on the device, so it's effectively one tap.
- **Sign in with Apple** is included because Apple's App Store guideline 4.8 *requires* it whenever an app offers another third-party social login (Google) - so on iOS it's mandatory, not optional.
- Flow: tap "Continue with Google/Apple" → OAuth round-trip → Supabase Auth creates the `auth.users` row and issues a session (JWT) → app checks "does this user have a profile?" → if no, force **Create Profile** screen (mandatory, one-time).
- Session persistence + token refresh handled automatically by `supabase_flutter`. Standard Supabase GoTrue session - `auth.uid()` works, RLS is idiomatic.

### Why this (auth decision log)

We evaluated three paths before locking this in:
- **Supabase phone-OTP + MSG91** - cheapest SMS (~₹0.15–0.25/OTP) but requires India DLT/TRAI registration and still costs per OTP.
- **Firebase Phone Auth** - rejected: verified ~₹6/OTP in India (not the myth of "10k free/month"; real free tier is ~10 SMS/*day*), needs Blaze billing, and forces a two-vendor split (empty `auth.users`, TEXT-keyed user ids, custom role-claim, first-token race, shared-signing-key RLS footgun).
- **Google/Apple social (chosen)** - genuinely ₹0 per signup forever, zero SMS, single vendor, keeps the clean Supabase-native data model. Trade-off accepted: phone is no longer a verified primary identifier (see §2, §3).

Phone-OTP can be added later as a secondary method if a real need appears; it is explicitly out of scope for v1 (§8).

## 2. Data model

Postgres tables (snake_case). RLS (row-level security) on every table.

### `profiles`
One row per authenticated user. PK = `id` (= `auth.users.id`).
| column | type | notes |
|---|---|---|
| id | uuid (PK, FK→auth.users) | populated by Supabase Auth on first social login |
| phone | text | **optional, user-entered, unverified** - used for guest-claim matching + search; null until the user adds it |
| display_name | text | required |
| photo_url | text | nullable; Supabase Storage |
| city | text | **free text** (no geo in v1) |
| batting_style | enum('right','left') | nullable |
| bowling_style | text | nullable (e.g. right-arm-fast, left-arm-spin) |
| playing_role | enum('batter','bowler','all_rounder','keeper') | nullable |
| created_at | timestamptz | default now() |

### `teams`
| column | type | notes |
|---|---|---|
| id | uuid (PK) | |
| name | text | required |
| logo_url | text | nullable |
| city | text | free text |
| created_by | uuid (FK→profiles) | the founding captain |
| created_at | timestamptz | |

### `team_members`
Join table. A user (or guest) can belong to **multiple teams**.
| column | type | notes |
|---|---|---|
| id | uuid (PK) | |
| team_id | uuid (FK→teams) | |
| profile_id | uuid (FK→profiles) | **nullable** - null when the member is a guest |
| guest_name | text | **nullable** - set when profile_id is null |
| role | enum('captain','admin','player') | default 'player' |
| created_at | timestamptz | |

Constraint: exactly one of (`profile_id`, `guest_name`) is non-null.

### `team_invites`
| column | type | notes |
|---|---|---|
| id | uuid (PK) | |
| team_id | uuid (FK→teams) | |
| invited_phone | text | nullable (search/request path) |
| invite_token | text (unique) | nullable (shareable-link path) |
| status | enum('pending','accepted','declined','expired') | default 'pending' |
| created_by | uuid (FK→profiles) | |
| created_at | timestamptz | |

## 3. Guest players + claim flow (the adoption mechanic)

The reason this app can spread without forcing 22 signups before a single match.

- A captain adds a roster member as a **guest**: just a `guest_name`, `profile_id = null`. No account needed. The guest can immediately appear in a scored match (sub-project #2) and accumulate stats against the `team_members` row.
- **Claiming:** later, when that person installs the app and signs in (Google/Apple), they can claim a guest entry. Primary path is a **captain-approved "this guest is me" request** (the captain knows who their players are). If the claimer has added a phone that matches one the captain attached to the guest, offer it as a **convenience auto-match** - but since phone is now optional/unverified (no phone-OTP), captain approval is the dependable mechanism, not phone.
- On claim: the `team_members` row's `profile_id` is filled in and `guest_name` cleared. Any history keyed to that membership row now belongs to the real profile.
- **v1 boundary:** captain-approved claim is the backbone; optional phone convenience-match on top. No fuzzy name-matching across teams in v1.

## 4. Core flows

1. **Onboard:** phone → OTP → Create Profile (name required; style/role optional) → home.
2. **Create team:** name + city (+ optional logo) → creator inserted into `team_members` as `captain`.
3. **Add players - two paths:**
   - **(a) Shareable invite link:** generates `team_invites.invite_token`; opening it (deep link) → "Join <Team>?" → accept → `team_members` row created with that profile.
   - **(b) Search + request:** search by name/phone → send invite (`invited_phone`) → invitee sees pending invite → accept/decline.
   - **(c) Add guest:** type a name → guest `team_members` row, no account.
4. **Manage roster:** captain/admin can promote/demote (player↔admin), remove members, convert nothing automatically (guest→real only via claim).

## 5. Authorization (RLS posture)

- A profile is readable by any authenticated user (needed for search, rosters, later social). Writable only by its owner.
- A team is readable by anyone (public team pages later). Writable (edit name/logo, manage members) only by its `captain`/`admin` members.
- `team_members` insert/update/delete gated to the team's captain/admin (except a user accepting their own invite).
- Enforced in Postgres RLS policies, not just client-side.

## 6. Error handling

- OAuth: user cancels the Google/Apple sheet, provider error, network failure mid-handshake → clear, retryable inline messages (never a dead-end).
- Profile gate: a signed-in user with no profile row is always routed back to Create Profile (can't slip into the app half-onboarded).
- Optimistic writes (create team, add member) with silent single retry; surface a non-blocking error toast only if retry fails.
- Duplicate guard: can't invite the same profile twice to one team; can't claim an already-claimed membership.

## 7. Testing

- Unit: RLS policy tests (can a non-admin mutate a roster? must fail), claim-flow state transitions, the "exactly one of profile_id/guest_name" constraint.
- Widget/integration (Flutter): onboarding happy path, create-team, add-guest, accept-invite, claim-guest.
- Manual: real Google + Apple sign-in round-trip on physical iOS and Android devices (OAuth redirect/URL-scheme config is the usual breakage point).

## 8. Explicitly out of scope (v1 of this sub-project)

- Geo / lat-long / "near me" (free-text city only).
- **Phone-OTP / SMS login** (social-only in v1; phone is an optional unverified profile field). Can be added as a secondary method later.
- Email / password login.
- Cross-team fuzzy identity resolution.
- Team-level chat / posts (that's sub-project #4).
- Any scoring (sub-project #2).

## Open items

- **OAuth provider setup** (build-time): Google OAuth client IDs (separate iOS / Android / web client IDs) wired into Supabase; Sign in with Apple capability + Service ID. Requires an **Apple Developer account ($99/yr)** - already needed for App Store distribution regardless.
- Exact deep-link scheme for invite links (Flutter `app_links`; note Firebase Dynamic Links is sunset, so use a plain custom-scheme / universal-link approach, not FDL).
