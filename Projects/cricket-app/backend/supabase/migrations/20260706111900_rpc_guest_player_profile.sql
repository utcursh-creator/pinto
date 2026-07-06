-- STAT-2: unclaimed guests finally have a career destination. Leaderboards and
-- rosters key guests by team_members.id; this composes an anon-safe profile for
-- that key: guest identity (name + team), career stats and recent form (both
-- already accept any player_key). If the member was CLAIMED, claimed_profile_id
-- lets the UI route to the richer /player/<profile> page instead.
create or replace function public.guest_player_profile(_member_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'member_id', tm.id,
    'name', coalesce(tm.guest_name, p.display_name, 'Player'),
    'team_name', t.name,
    'claimed_profile_id', tm.profile_id,
    'career', public.player_career_stats(tm.id),
    'recent_form', public.player_recent_form(tm.id, 5))
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  left join public.profiles p on p.id = tm.profile_id
  where tm.id = _member_id;
$$;
revoke all on function public.guest_player_profile(uuid) from public;
grant execute on function public.guest_player_profile(uuid) to anon, authenticated;
