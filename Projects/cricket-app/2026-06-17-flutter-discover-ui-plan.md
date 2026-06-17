---
type: plan
category: frontend
project: cricket-app
date: 2026-06-17
status: in-progress
sub_project: 5
slice: 3
---

# Flutter Discover / Matchmaking UI - build plan (slice 3, the headline)

Wires the geo-matchmaking feed + replies + realtime 1:1 DMs to the live backend. Green bar: analyze clean + widget tests + live-query verification + runs on sim.

## Backend facts (verified)
- `discover_posts(_lat,_lng,_radius_m=25000,_mode?,_max_overs?,_on_or_after?,_skill?,_flair?)` -> rows {post_id, author_id, team_id, mode, flair, title, description, place_label, match_at, overs, skill, slots_needed, created_at, approx_m}. No coords returned.
- `create_looking_for_post(_mode, _flair, _lat, _lng, _description?, _team_id?, _title?, _match_at?, _overs?, _skill?, _slots_needed?, _place_label?, _expires_at?)` -> post id. _flair REQUIRED (loser_pays|practice_match|corporate_match). team_seeking_* needs a _team_id the caller admins.
- `cancel_post(id)`, `mark_post_filled(id)` (author-gated).
- `post_replies` (post_id, author_id, body) - read all authed, write own. `looking_for_posts` read all authed.
- DM: `get_or_create_dm_thread(_other)` -> thread id (idempotent). `dm_messages` (thread_id, sender_id, body) - participant-gated RLS. Realtime: trigger broadcast_changes on channel `dm:<thread_id>`, receive policy participant-scoped authenticated + client must use private channel + setAuth.
- enums: lf_mode (player_seeking_team|team_seeking_players|team_seeking_opponent), lf_flair, skill_level (beginner|intermediate|advanced).

## Location anchor (scoping decision)
Real device GPS (geolocator) deferred. v1: an `anchorProvider` (Notifier) defaulting to Mumbai (19.07, 72.87); a small Location screen lets the user set lat/lng + a radius. discover_posts uses the anchor. "Near me (GPS)" added in a refinement.

## Data layer (features/discover/data)
- `discover_repository.dart`: createPost(...), reply(postId, body), cancelPost/markFilled, getOrCreateDmThread(other), sendDm(threadId, body).
- `discover_providers.dart`: `discoverFeedProvider` (FutureProvider.family over a DiscoverQuery {lat,lng,radius,mode?,flair?}), `postRepliesProvider.family(postId)`, `dmInboxProvider`, `dmThreadMessagesProvider.family(threadId)` (initial fetch + realtime append), `anchorProvider`.
- `discover_models.dart`: small DiscoverQuery value type; flair/mode label maps.

## Screens (features/discover/presentation + features/messages/presentation)
1. discover_screen.dart (REPLACE placeholder): mode filter chips + flair pills + distance per card (approx_m) + Reply/Message actions; FAB New post; entry to Messages + Location. Reads discoverFeedProvider(anchor+filters).
2. filters_sheet.dart: mode / radius / skill / flair (adaptive bottom sheet / form sheet).
3. new_post_composer.dart: mode segmented, REQUIRED flair chips, location (anchor), when/overs/slots/details -> create_looking_for_post. team_seeking_* -> pick one of my admin teams.
4. post_detail_screen.dart: post header (flair, distance, meta) + replies list + reply composer + Message author.
5. messages: dm_inbox_screen.dart (threads w/ latest preview), dm_thread_screen.dart (messages + realtime append + send).
6. my_posts_screen.dart (the audit gap): author's posts with cancel / mark-filled.
7. location_screen.dart: set anchor lat/lng + radius (GPS deferred).

## Routing
Discover branch: /discover + sub-routes post/:id, compose, filters, location, messages, messages/:threadId, my-posts. Drill via context.push.

## Out of scope (this slice)
Real GPS (geolocator), push notifications, the discover->match bridge (needs slice 4 match-setup; build the bridge when scoring exists), group chat.

## Verify
analyze clean; widget tests (feed renders from overridden provider with flair+distance; composer requires flair; post detail renders replies). Live: as the seeded dev user, create a post via RPC, discover it, reply, open a DM, send a message, confirm realtime delivery. Run on sim.
