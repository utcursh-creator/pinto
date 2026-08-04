-- Whole-system review #2 (2026-07-28), finding 56 - and a larger hole of the
-- same shape found while verifying it.
--
-- THE RECORDED FINDING: delete_match refuses to touch a match that belongs to a
-- tournament, because removing it would corrupt the standings. But
-- `grant delete on public.matches to authenticated` plus policy
-- matches_delete_owner (owner_id = auth.uid()) was still in force, and every
-- generated fixture is owned by the organizer. One
-- `DELETE /rest/v1/matches?id=eq.<fixture>` and the innings, deliveries,
-- match_squad and tournament_matches rows all cascade away; standings, NRR and
-- the qualifying two per group silently change, and generate_playoffs seeds the
-- wrong teams. The RPC's guard was decorative.
--
-- THE LARGER HOLE: deliveries, innings and match_squad each had an ALL-command
-- policy for the match scorer plus the matching table grants. The entire
-- scoring engine is RPC-fronted - record_ball alone enforces the
-- consecutive-over rule, the bowler quota, which dismissals are legal off a
-- wide or a no-ball, the incoming-batter requirement and the expected_last_seq
-- concurrency token, and every mutation re-runs the three lockstep folds. A
-- scorer with any HTTP client could bypass all of it: insert a delivery that is
-- bowled off a wide, rewrite seq or is_legal so the folds disagree, or delete a
-- ball without the strike restamp. Those records are not private - they are
-- tournament standings and other players' career statistics.
--
-- The client never used any of these paths; it has always gone through the
-- RPCs. Every function that writes these tables is SECURITY DEFINER (all 22
-- checked), so removing the grants closes the side door without touching the
-- front one.
--
-- The `20260707130100_revoke_direct_writes` batch fixed exactly this pattern
-- for tournament_teams, tournament_matches, matches UPDATE and
-- tournament_invites. Its own comment kept matches DELETE on the belief that
-- "delete_match fronts it" - which is not what a table-level grant means.

revoke insert, update, delete on public.deliveries  from authenticated, anon;
revoke insert, update, delete on public.innings     from authenticated, anon;
revoke insert, update, delete on public.match_squad from authenticated, anon;
revoke delete on public.matches from authenticated, anon;

-- The write policies are now unreachable, and a policy that says "the scorer
-- may write this table" when they may not is precisely the kind of statement
-- that reads as a guarantee and is not one. Drop them; the SELECT policies are
-- separate and untouched, so viewing a scorecard is unaffected.
drop policy if exists "deliveries_write_scorer"  on public.deliveries;
drop policy if exists "innings_write_scorer"     on public.innings;
drop policy if exists "match_squad_write_scorer" on public.match_squad;
drop policy if exists "matches_delete_owner"     on public.matches;

-- NOTE deliberately NOT revoked: insert on public.matches. create_match is
-- SECURITY DEFINER, but the direct grant is still constrained by
-- matches_insert_participant (owner = caller AND caller admins one of the two
-- teams AND scorer = caller), which is the CRITICAL fix from earlier in this
-- review and is pinned by pgTAP 120. Revoking it would make that policy dead
-- code; leaving it means two independent guards instead of one.
