-- RT-2: the live premise only pushes on deliveries today, so a new 2nd innings
-- (an INSERT on innings) and a match completion (an UPDATE of matches.status/
-- result) never reach the watcher. Add AFTER triggers on innings + matches that
-- broadcast on the SAME `match:<id>` topic the delivery trigger uses, so a
-- watcher re-folds on the innings change and the result appears without a reopen.
-- SEC-10: log the failure with `raise warning` instead of swallowing silently,
-- but still never abort the write.

create or replace function public.broadcast_innings_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare _rec public.innings := coalesce(NEW, OLD);
begin
  perform realtime.broadcast_changes(
    'match:' || _rec.match_id::text,
    tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then
  raise warning 'broadcast_innings_change failed: %', sqlerrm;
  return null;
end; $$;

create trigger innings_broadcast
  after insert or update on public.innings
  for each row execute function public.broadcast_innings_change();

create or replace function public.broadcast_match_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare _rec public.matches := coalesce(NEW, OLD);
begin
  perform realtime.broadcast_changes(
    'match:' || _rec.id::text,
    tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then
  raise warning 'broadcast_match_change failed: %', sqlerrm;
  return null;
end; $$;

-- Only push when something a watcher cares about changed (status / result),
-- not on every toss/venue edit during setup.
create trigger matches_broadcast
  after update on public.matches
  for each row
  when (old.status is distinct from new.status or old.result is distinct from new.result)
  execute function public.broadcast_match_change();
