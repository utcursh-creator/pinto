-- MISS-6 / TEAM-2 / TEAM-3 / SEC-7: the shareable team invite was single-use-
-- then-dead (first tapper consumed it for everyone) and a leaked token granted
-- membership forever. Now an invite is MULTI-USE by default (share one link
-- with the whole squad), EXPIRES after 7 days, supports an optional max_uses
-- cap, and can be REVOKED by an admin (status -> 'expired', RLS already allows
-- the admin update). The token row is locked (select ... for update) during
-- redemption so concurrent tappers cannot race past the caps.
alter table public.team_invites
  add column expires_at timestamptz not null default (now() + interval '7 days');
alter table public.team_invites add column max_uses int;
alter table public.team_invites add column uses int not null default 0;

create or replace function public.accept_invite(_invite_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _team_id uuid; _status public.invite_status; _exp timestamptz;
  _uses int; _max int; _membership_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Lock the row: concurrent redeemers serialize here (TEAM-3 TOCTOU fix).
  select team_id, status, expires_at, uses, max_uses
    into _team_id, _status, _exp, _uses, _max
    from public.team_invites
    where invite_token = _invite_token
    for update;

  if _team_id is null or _status <> 'pending' then
    raise exception 'invite not found or already used' using errcode = 'P0001';
  end if;
  if _exp < now() then
    raise exception 'invite expired' using errcode = 'P0001';
  end if;
  if _max is not null and _uses >= _max then
    raise exception 'invite fully used' using errcode = 'P0001';
  end if;

  -- Concurrency-safe join: rely on the partial unique index, not read-then-insert.
  insert into public.team_members (team_id, profile_id, role)
  values (_team_id, auth.uid(), 'player')
  on conflict (team_id, profile_id) where profile_id is not null
  do nothing
  returning id into _membership_id;

  if _membership_id is null then
    -- already a member: return their row and do NOT burn a use
    select id into _membership_id
    from public.team_members
    where team_id = _team_id and profile_id = auth.uid();
  else
    update public.team_invites set uses = uses + 1
      where invite_token = _invite_token;
  end if;

  return _membership_id;
end;
$$;
revoke all on function public.accept_invite(text) from public;
grant execute on function public.accept_invite(text) to authenticated;

-- The pre-flight now reflects the multi-use semantics.
create or replace function public.team_invite_preview(_invite_token text)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'team_name', t.name,
    'status', i.status,
    'redeemable', (i.status = 'pending'
                   and i.expires_at > now()
                   and (i.max_uses is null or i.uses < i.max_uses)))
  from public.team_invites i
  join public.teams t on t.id = i.team_id
  where i.invite_token = _invite_token;
$$;
revoke all on function public.team_invite_preview(text) from public;
grant execute on function public.team_invite_preview(text) to authenticated, anon;

-- The inviter notification now keys off a use being consumed (the status no
-- longer flips to 'accepted' on redemption).
create or replace function public.notify_invite_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
declare _team text;
begin
  if NEW.uses > OLD.uses then
    select name into _team from public.teams where id = NEW.team_id;
    insert into public.notifications(recipient_id, type, ref_id, body)
    values (NEW.created_by, 'invite_accepted', NEW.team_id,
            'Someone joined ' || coalesce(_team, 'your team') || ' via your invite');
  end if;
  return null;
exception when others then
  raise warning 'notify_invite_accepted failed: %', sqlerrm;
  return null;
end; $$;
