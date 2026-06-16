create or replace function public.get_or_create_dm_thread(_other uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare _me uuid := (select auth.uid()); _lo uuid; _hi uuid; _id uuid;
begin
  if _me is null then raise exception 'not authenticated' using errcode='28000'; end if;
  if _other = _me then raise exception 'cannot DM yourself' using errcode='P0001'; end if;
  _lo := least(_me, _other); _hi := greatest(_me, _other);
  insert into public.dm_threads(user_lo, user_hi) values (_lo, _hi)
    on conflict (user_lo, user_hi) do nothing;
  select id into _id from public.dm_threads where user_lo=_lo and user_hi=_hi;
  insert into public.dm_participants(thread_id, profile_id) values (_id, _lo), (_id, _hi)
    on conflict do nothing;
  return _id;
end; $$;
revoke all on function public.get_or_create_dm_thread(uuid) from public;
grant execute on function public.get_or_create_dm_thread(uuid) to authenticated;
