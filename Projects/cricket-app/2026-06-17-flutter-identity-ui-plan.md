---
type: plan
category: frontend
project: cricket-app
date: 2026-06-17
status: in-progress
sub_project: 5
slice: 2
---

# Flutter Identity UI - build plan (sub-project 5, slice 2)

Builds the first real feature screens on the foundation, wired to the live Identity backend. Green bar: `flutter analyze` clean + widget tests pass + runs on the iOS simulator. Brand teal, platform-adaptive chrome (reuses AdaptiveScaffold + the foundation's MaterialApp/Cupertino theming).

## Backend facts (verified)
- Tables (all SELECT `using(true)` to authenticated; writes owner/admin-gated): `profiles` (id, phone, display_name, photo_url, city, batting_style enum right|left, bowling_style text, playing_role enum batter|bowler|all_rounder|keeper), `teams` (id, name, city, logo_url, created_by), `team_members` (id, team_id, profile_id, guest_name, role enum captain|admin|player, bats enum RHB|LHB).
- RPCs: `create_team(_name, _city?, _logo_url?) -> team_id`, `add_guest_member(_team_id, _guest_name) -> membership_id`.
- FKs for embedded selects: team_members.team_id->teams.id, team_members.profile_id->profiles.id.

## Data layer (Riverpod 3.x, manual providers)
- `features/identity/data/identity_repository.dart`: `IdentityRepository` (behind `identityRepositoryProvider`): `updateMyProfile(Map)`, `createTeam(name, city)`, `addGuest(teamId, name)`.
- `features/identity/data/identity_providers.dart`:
  - `myTeamsProvider` FutureProvider -> `from('team_members').select('role, teams(*)').eq('profile_id', uid)`.
  - `teamProvider` FutureProvider.family<Map?, String> -> `from('teams').select().eq('id', id).maybeSingle()`.
  - `teamRosterProvider` FutureProvider.family<List, String> -> `from('team_members').select('id, role, guest_name, profile_id, profiles(display_name, photo_url)').eq('team_id', id)`.
- Reuse `myProfileProvider` (core/auth) for the own-profile read; invalidate it after edits.

## Screens
1. `profile/presentation/profile_screen.dart` (REPLACE placeholder): avatar(initials) + name + city + style/role line; row -> Edit, My teams, Settings(stub); Sign out (real, client.auth.signOut). Reads myProfileProvider.
2. `profile/presentation/edit_profile_screen.dart`: form (display_name, phone, city, batting segmented right|left, role segmented, bowling_style text) -> updateMyProfile + invalidate myProfileProvider -> pop.
3. `teams/presentation/my_teams_screen.dart`: list myTeams (name, city, role chip) -> tap opens team page; + Create team.
4. `teams/presentation/create_team_screen.dart`: name + city -> createTeam rpc -> replace to team page.
5. `teams/presentation/team_page_screen.dart`: team header (name, city) + roster list (real members via profiles join, guests via guest_name, role chip) + (admin only) Add guest. Reads teamProvider + teamRosterProvider.

## Routing (nested under the Profile branch so drill-ins keep the tab + get a back button)
- /profile (existing) + sub-routes: edit, teams, teams/create, teams/:teamId. Drill-in via context.push(absolute path). AdaptiveScaffold's nav bar auto-shows back.

## Out of scope (later)
- Photo/logo upload (needs a Storage bucket) - show initials avatars; deferred.
- Invite links / phone invites / guest-claim approval / pending-invites / other-player profile (later identity sub-slice).
- Real Google/Apple login (still the dev-auth shim).

## Verify
- `flutter analyze` clean.
- Widget tests: profile renders from an overridden myProfileProvider; My teams renders an overridden myTeamsProvider list; create-team form validation. Override the repo/providers (no live backend in tests).
- Run on iOS simulator against the live local stack: dev sign-in -> create profile -> Profile tab shows it -> create a team -> see it in My teams -> open team page. Screenshot.
