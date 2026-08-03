-- CRITICAL (whole-system review #2, 2026-07-28): the SEC-5 team-admin gate on
-- create_match was bypassable, because the TABLE still granted INSERT under a
-- policy that only checked `owner_id = auth.uid()`. team_a_id, team_b_id and
-- scorer_id were unchecked.
--
-- One PostgREST call made an attacker the scorer of a match between two clubs
-- she had nothing to do with, and every downstream guard then passed because
-- each one only asks "are you the scorer?" - add_squad_member accepted the
-- victims' real players, start_innings flipped it live and notified every squad
-- member, record_ball and set_match_result completed it. The fabricated game
-- counted in both victims' public team_career_stats and folded into real
-- players' career records, readable with no login, and neither victim could
-- remove it (delete_match and matches_delete_owner both require ownership, and
-- transfer_scorer refuses once status is 'complete').
--
-- This is precisely the shape 20260707130100_revoke_direct_writes.sql was
-- written to close - "the RPC holds the rule, but the TABLE is still granted".
-- That migration revoked UPDATE on matches and left INSERT open, saying so in a
-- comment. The rule the policy was missing is PARTICIPATION, which is the same
-- rule create_match enforces.
--
-- Note the shape of the fix: the policy expresses the RULE, not "only the RPC
-- may write". An admin of a participating team can still insert directly; a
-- stranger cannot, whichever door they use.

drop policy if exists "matches_insert_own" on public.matches;

create policy "matches_insert_participant"
  on public.matches for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    -- SEC-5, now enforced at the table: you must be an admin of one of the two
    -- teams actually playing.
    and (public.is_team_admin(team_a_id) or public.is_team_admin(team_b_id))
    -- and you cannot install someone else as the scorer on creation; the
    -- transfer_scorer RPC is the only way to hand scoring over, and it has its
    -- own authorization and status rules.
    and scorer_id = (select auth.uid())
  );
