-- DISC-8: pre-flight for the /invite/:token screen. Resolves a token to the
-- inviting team's name + whether it is still redeemable, WITHOUT exposing the
-- invite row (team_invites is admin-only readable). Returns null when the token
-- does not exist, so the screen can show a clear invalid state instead of a raw
-- error after tapping Join.
create or replace function public.team_invite_preview(_invite_token text)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'team_name', t.name,
    'status', i.status,
    'redeemable', (i.status = 'pending'))
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  where i.invite_token = _invite_token;
$$;
revoke all on function public.team_invite_preview(text) from public;
grant execute on function public.team_invite_preview(text) to authenticated, anon;
