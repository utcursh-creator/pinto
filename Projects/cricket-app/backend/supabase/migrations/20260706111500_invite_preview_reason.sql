-- DISC-8: the invite preview says WHY a token is dead, so the join screen can
-- tell "this invite expired" from "already used" / "revoked" instead of one
-- generic failure line. accept_invite already raises distinct messages; this
-- aligns the pre-flight.
create or replace function public.team_invite_preview(_invite_token text)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'team_name', t.name,
    'status', i.status,
    'redeemable', (i.status = 'pending' and i.expires_at > now()
                   and (i.max_uses is null or i.uses < i.max_uses)),
    'reason', case
      when i.status = 'accepted' then 'used'
      when i.status <> 'pending' then 'revoked'   -- declined / admin-revoked (stored as expired)
      when i.expires_at <= now() then 'expired'
      when i.max_uses is not null and i.uses >= i.max_uses then 'used_up'
      else null end)
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  where i.invite_token = _invite_token;
$$;
revoke all on function public.team_invite_preview(text) from public;
grant execute on function public.team_invite_preview(text) to authenticated, anon;
