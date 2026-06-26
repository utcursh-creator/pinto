-- Mint a shareable invite token for a team (admin only). The token is generated
-- server-side (not client-supplied) so it is unguessable. Redeem with the
-- existing accept_invite(token). This is what makes inviting a REGISTERED player
-- reachable - guest-add + guest-claim cover the no-account path.
create or replace function public.create_team_invite(_team_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare _token text;
begin
  if not public.is_team_admin(_team_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  _token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  insert into public.team_invites(team_id, invite_token, created_by, status)
  values (_team_id, _token, (select auth.uid()), 'pending');
  return _token;
end; $$;

revoke all on function public.create_team_invite(uuid) from public;
grant execute on function public.create_team_invite(uuid) to authenticated;
