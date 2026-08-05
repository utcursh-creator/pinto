# Pre-finding (found by me, 2026-08-05, while review #3 was running)

## looking_for_posts: authenticated holds UPDATE on EVERY column, so every posts RPC guard is optional

`information_schema.role_column_grants` shows `authenticated` with UPDATE on all of:
  id, author_id, team_id, mode, title, description, geog, geog_coarse, place_label,
  match_at, overs, skill, slots_needed, status, expires_at, created_at, flair,
  image_urls, link_url, ball_type

RLS policy `posts_update_author :: author_id = (select auth.uid())` limits it to your OWN
post - and since the policy has no separate WITH CHECK, it also blocks handing the post to
somebody else. So this is not a takeover. What it IS:

* **expires_at is client-settable** -> a post can be kept in the feed forever, which is
  precisely the silting the expiry work (20260707160000) exists to stop, and it walks
  straight around `renew_post`'s "give this post a new date" guard.
* **status is client-settable** -> a cancelled or filled post can be flipped back to
  'open', around `cancel_post` / `mark_post_filled` and around renew_post's refusal to
  resurrect them ("a decision is not an accident" - pgTAP 145 asserts the RPC refuses;
  nothing asserts the TABLE does).
* **geog and geog_coarse are client-settable** -> `_snap_geog` coarsens location to ~0.005
  degrees on the way in, and `create_looking_for_post` is the only thing that computes
  geog_coarse. A PATCH can put an ad at any coordinate on earth: spam a distant city's
  feed, or defeat the coarsening the privacy design depends on.

This is the SAME SHAPE as review #2 finding 6 (matches INSERT) and the deliveries/
match_squad revocations: a table-level grant that makes the RPC's guards decorative.
The fix is the same - revoke UPDATE (and DELETE, which is also granted) on
looking_for_posts from authenticated, and route the two legitimate edits (cancel, mark
filled, renew) through the RPCs that already exist.

CHECKED AND *NOT* A PROBLEM (do not "fix" these):
* team_members DELETE is granted, but every FK from match_squad / innings / deliveries is
  ON DELETE NO ACTION, so Postgres REFUSES to delete a member with match history. The
  tombstone design is enforced by the database, not only by leave_team.
  (guest_claim_requests is ON DELETE CASCADE, which is right.)
* 0 SECURITY DEFINER functions are missing a pinned search_path.
* 0 function overloads (nothing left behind by a create-or-replace with a new arity).
* 5 policies still use a bare auth.uid() (profiles_insert_own, profiles_update_own,
  teams_insert_own, team_invites_insert_admin, team_members_delete_admin_or_self). All
  five act on a SINGLE row - an insert of one row, an update of your own profile, a delete
  of one membership - so hoisting into an InitPlan buys nothing measurable. Review #2's
  finding 73 was about a table SCAN. Leaving these alone deliberately.
