-- MISS-2: the notification writers. All AFTER triggers, SECURITY DEFINER, and
-- - like the broadcast triggers - a failure logs a warning but never aborts the
-- write that caused it.

-- A reply to your looking-for post.
create or replace function public.notify_post_reply()
returns trigger language plpgsql security definer set search_path = public as $$
declare _author uuid; _who text;
begin
  select author_id into _author from public.looking_for_posts where id = NEW.post_id;
  if _author is not null and _author <> NEW.author_id then
    select display_name into _who from public.profiles where id = NEW.author_id;
    insert into public.notifications(recipient_id, type, ref_id, body)
    values (_author, 'post_reply', NEW.post_id,
            coalesce(_who, 'Someone') || ' replied to your post');
  end if;
  return null;
exception when others then
  raise warning 'notify_post_reply failed: %', sqlerrm; return null;
end; $$;
create trigger post_replies_notify
  after insert on public.post_replies
  for each row execute function public.notify_post_reply();

-- A new DM. One unread 'dm' notification per thread per recipient at a time,
-- so a burst of messages doesn't flood the inbox.
create or replace function public.notify_dm_message()
returns trigger language plpgsql security definer set search_path = public as $$
declare _other uuid; _who text;
begin
  select profile_id into _other from public.dm_participants
    where thread_id = NEW.thread_id and profile_id <> NEW.sender_id limit 1;
  if _other is not null and not exists (
    select 1 from public.notifications
    where recipient_id = _other and type = 'dm' and ref_id = NEW.thread_id
      and read_at is null
  ) then
    select display_name into _who from public.profiles where id = NEW.sender_id;
    insert into public.notifications(recipient_id, type, ref_id, body)
    values (_other, 'dm', NEW.thread_id,
            'New message from ' || coalesce(_who, 'someone'));
  end if;
  return null;
exception when others then
  raise warning 'notify_dm_message failed: %', sqlerrm; return null;
end; $$;
create trigger dm_messages_notify
  after insert on public.dm_messages
  for each row execute function public.notify_dm_message();

-- A guest-claim request lands with the team's captain(s)/admin(s).
create or replace function public.notify_claim_request()
returns trigger language plpgsql security definer set search_path = public as $$
declare _team uuid; _who text; _guest text;
begin
  select team_id, guest_name into _team, _guest
    from public.team_members where id = NEW.membership_id;
  select display_name into _who from public.profiles where id = NEW.requested_by;
  insert into public.notifications(recipient_id, type, ref_id, body)
  select tm.profile_id, 'claim_request', NEW.membership_id,
         coalesce(_who, 'Someone') || ' says they are ' ||
         coalesce(_guest, 'a guest player') || ' - review the claim'
  from public.team_members tm
  where tm.team_id = _team and tm.role in ('captain', 'admin')
    and tm.profile_id is not null and tm.profile_id <> NEW.requested_by;
  return null;
exception when others then
  raise warning 'notify_claim_request failed: %', sqlerrm; return null;
end; $$;
create trigger guest_claims_notify
  after insert on public.guest_claim_requests
  for each row execute function public.notify_claim_request();

-- Your team invite was accepted.
create or replace function public.notify_invite_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
declare _team text;
begin
  if OLD.status = 'pending' and NEW.status = 'accepted' then
    select name into _team from public.teams where id = NEW.team_id;
    insert into public.notifications(recipient_id, type, ref_id, body)
    values (NEW.created_by, 'invite_accepted', NEW.team_id,
            'Your invite to ' || coalesce(_team, 'your team') || ' was accepted');
  end if;
  return null;
exception when others then
  raise warning 'notify_invite_accepted failed: %', sqlerrm; return null;
end; $$;
create trigger team_invites_notify
  after update on public.team_invites
  for each row execute function public.notify_invite_accepted();

-- The match you are in went live: tell the registered squad members (except
-- whoever is scoring - they started it).
create or replace function public.notify_match_live()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if OLD.status = 'setup' and NEW.status = 'live' then
    insert into public.notifications(recipient_id, type, ref_id, body)
    select distinct tm.profile_id, 'match_live', NEW.id, 'Your match is live - follow the score'
    from public.match_squad ms
    join public.team_members tm on tm.id = ms.team_member_id
    where ms.match_id = NEW.id
      and tm.profile_id is not null and tm.profile_id <> NEW.scorer_id;
  end if;
  return null;
exception when others then
  raise warning 'notify_match_live failed: %', sqlerrm; return null;
end; $$;
create trigger matches_live_notify
  after update on public.matches
  for each row execute function public.notify_match_live();
