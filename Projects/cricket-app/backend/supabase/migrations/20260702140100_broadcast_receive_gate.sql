-- SEC-9: the match broadcast receive policy authorized ANY `match:%` topic with
-- no check that the match is actually public - so any future setup-time broadcast
-- would leak. Gate it on the match being publicly viewable, mirroring the table
-- policies (status not 'setup') and the DM policy's split_part(topic) pattern.
create or replace function public.match_is_publicly_viewable(_match_id uuid)
returns boolean language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from public.matches
    where id = _match_id
      and status in ('live','innings_break','complete','abandoned')
  );
$$;
revoke all on function public.match_is_publicly_viewable(uuid) from public;
grant execute on function public.match_is_publicly_viewable(uuid) to authenticated, anon;

drop policy if exists "match_broadcast_receive" on realtime.messages;
create policy "match_broadcast_receive" on realtime.messages
  for select to authenticated, anon
  using (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'match:%'
    and public.match_is_publicly_viewable((split_part(realtime.topic(), ':', 2))::uuid)
  );
