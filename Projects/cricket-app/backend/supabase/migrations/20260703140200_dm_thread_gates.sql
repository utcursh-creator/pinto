-- SEC-3 (part 2): harden get_or_create_dm_thread. The open version let any
-- authenticated user DM any UUID with no consent, block, or rate limit. Now:
--  * the target must have a real profile (anonymous-only accounts have none),
--  * a block in either direction closes the channel,
--  * creating NEW threads is rate-limited (10/hour per creator) so a harasser
--    cannot spray conversations; reopening an existing thread is never limited.
-- A relationship-strict gate was considered and deliberately NOT used: the
-- people-picker (DM-7) and propose-match (MTCH-7) flows message players you have
-- no prior row with; block + rate limit is the sanctioned lighter option.
alter table public.dm_threads add column created_by uuid references public.profiles(id);

create or replace function public.get_or_create_dm_thread(_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare _me uuid := (select auth.uid()); _lo uuid; _hi uuid; _id uuid;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _other = _me then raise exception 'cannot DM yourself' using errcode='P0001'; end if;
  if not exists (select 1 from public.profiles where id = _other) then
    raise exception 'user not found' using errcode='P0001';
  end if;
  if public.is_blocked_between(_other) then
    raise exception 'you cannot message this user' using errcode='P0001';
  end if;

  _lo := least(_me, _other); _hi := greatest(_me, _other);
  select id into _id from public.dm_threads where user_lo=_lo and user_hi=_hi;
  if _id is not null then return _id; end if;  -- existing thread: never limited

  if (select count(*) from public.dm_threads
      where created_by = _me and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'too many new conversations - try again later' using errcode='P0001';
  end if;

  insert into public.dm_threads(user_lo, user_hi, created_by) values (_lo, _hi, _me)
    on conflict (user_lo, user_hi) do nothing;
  select id into _id from public.dm_threads where user_lo=_lo and user_hi=_hi;
  insert into public.dm_participants(thread_id, profile_id) values (_id, _lo), (_id, _hi)
    on conflict do nothing;
  return _id;
end; $$;
revoke all on function public.get_or_create_dm_thread(uuid) from public;
grant execute on function public.get_or_create_dm_thread(uuid) to authenticated;
