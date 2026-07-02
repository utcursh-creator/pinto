-- Mint a shareable tournament join token (organizer only, while still in setup).
-- Mirrors create_team_invite: server-generated unguessable token, redeemed with
-- join_tournament_with_token. This is what lets a team the organizer does NOT
-- admin enter the tournament - by that team's own admin opting in.
create or replace function public.create_tournament_invite(_tournament_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare _token text;
begin
  if not public.is_tournament_organizer(_tournament_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if (select status from public.tournaments where id = _tournament_id) <> 'setup' then
    raise exception 'tournament is not in setup' using errcode = 'P0001';
  end if;
  _token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.tournament_invites(tournament_id, invite_token, created_by, status)
  values (_tournament_id, _token, (select auth.uid()), 'pending');
  return _token;
end; $$;
revoke all on function public.create_tournament_invite(uuid) from public;
grant execute on function public.create_tournament_invite(uuid) to authenticated;
