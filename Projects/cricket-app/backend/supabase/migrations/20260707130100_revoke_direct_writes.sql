-- HIGH batch (penetration review 2026-07-07): "the RPC holds the rule, but the
-- TABLE is still granted" - the single most repeated root cause in the review.
-- Every hardened SECURITY DEFINER RPC below was bypassable with one PostgREST
-- call against the base table. Tests 108 reproduce all of them.

-- 1. tournament_teams: tt_write_organizer only checked the TOURNAMENT side, so
--    an organizer could enrol ANY team - the exact unconsented insert the SEC-8
--    consent model exists to prevent. add_tournament_team (organizer AND
--    team-admin) and join_tournament_with_token (team-admin redeems) are the
--    only legitimate write paths, and both are SECURITY DEFINER, so the client
--    needs no table-level write at all.
drop policy "tt_write_organizer" on public.tournament_teams;
revoke insert, update, delete on public.tournament_teams from authenticated;

-- 2. tournament_matches: match_id was entirely unvalidated, so any user could
--    attach a STRANGER'S match to a tournament they own - which both handed
--    them update_match_schedule authority over it (that RPC trusts this link)
--    and permanently blocked the real owner from deleting their own match
--    (delete_match refuses anything with a tournament_matches row). Fixtures are
--    only ever created by generate_group_fixtures / generate_playoffs /
--    advance_playoffs, all SECURITY DEFINER.
drop policy "tm_write_organizer" on public.tournament_matches;
revoke insert, update, delete on public.tournament_matches from authenticated;

-- 3. matches: a blanket UPDATE grant made every guard in set_match_result
--    (SEC-6/MTCH-3: winner must be one of THIS match's teams, no re-resulting a
--    terminal match) and update_match_schedule decorative - a scorer could PATCH
--    result/status/potm/team ids straight onto the row and fabricate a public
--    record for a team that never played.
--    The client keeps INSERT (matches_insert_own) and DELETE (matches_delete_owner,
--    which delete_match also fronts); UPDATE now belongs to the RPCs only.
drop policy "matches_update_scorer" on public.matches;
revoke update on public.matches from authenticated;

-- the one legitimate direct UPDATE the app had left, as its own narrow RPC
create or replace function public.set_toss(
  _match_id uuid, _winner_team_id uuid, _decision public.toss_decision
) returns void language plpgsql security definer set search_path = public as $$
declare _a uuid; _b uuid; _st public.match_status;
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  select team_a_id, team_b_id, status into _a, _b, _st
    from public.matches where id = _match_id;
  if _a is null then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _st in ('complete','abandoned') then
    raise exception 'this match already finished' using errcode = 'P0001';
  end if;
  if _winner_team_id is distinct from _a and _winner_team_id is distinct from _b then
    raise exception 'the toss winner must be one of the two teams in this match'
      using errcode = 'P0001';
  end if;
  update public.matches
     set toss_winner_id = _winner_team_id, toss_decision = _decision
   where id = _match_id;
end; $$;
revoke all on function public.set_toss(uuid, uuid, public.toss_decision) from public;
grant execute on function public.set_toss(uuid, uuid, public.toss_decision) to authenticated;

-- 4. posts_update_author: the WITH CHECK omitted the team-admin condition the
--    INSERT path enforces, so an author could re-point their own post at a team
--    they do not administer and post in that team's name.
drop policy if exists "posts_update_author" on public.looking_for_posts;
create policy "posts_update_author" on public.looking_for_posts
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (
    author_id = (select auth.uid())
    and (team_id is null or public.is_team_admin(team_id))
  );

-- 5. tournament_invites had an unused delete grant; minting/redeeming is all
--    SECURITY DEFINER.
revoke insert, update, delete on public.tournament_invites from authenticated;
