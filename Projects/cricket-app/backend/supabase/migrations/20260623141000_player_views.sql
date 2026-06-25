-- Identity rollup for stats. player_key = COALESCE(profile_id, member_id):
-- a claimed user rolls up across their per-team memberships under their profile
-- id; an unclaimed guest keys by membership id (no standalone public page until
-- claimed). Because approve_guest_claim rewrites profile_id in place on the same
-- team_members row, and every delivery actor column references team_members(id),
-- a claim re-keys the guest's entire history to the claimer at READ time with
-- zero backfill - the views simply recompute the key.
--
-- security_invoker = true so these respect the caller's RLS (no privilege
-- escalation). Inside the SECURITY DEFINER career RPCs the effective role is the
-- owner, so they see all completed matches; granted to authenticated for direct
-- use, never to anon (anon reaches stats only through the definer RPCs).
create view public.v_player_key with (security_invoker = true) as
  select tm.id as member_id,
         coalesce(tm.profile_id, tm.id) as player_key,
         tm.profile_id
  from public.team_members tm;

-- Matches played per player_key, from match_squad (the definitive who-played
-- record). Status in (complete, abandoned) per the matches-played policy;
-- averages fold only complete matches (handled in the career RPC).
create view public.v_player_matches with (security_invoker = true) as
  select distinct coalesce(tm.profile_id, tm.id) as player_key,
         ms.match_id,
         ms.team_id
  from public.match_squad ms
  join public.team_members tm on tm.id = ms.team_member_id
  join public.matches m on m.id = ms.match_id
  where m.status in ('complete','abandoned');

revoke all on public.v_player_key from public;
revoke all on public.v_player_matches from public;
grant select on public.v_player_key to authenticated;
grant select on public.v_player_matches to authenticated;
