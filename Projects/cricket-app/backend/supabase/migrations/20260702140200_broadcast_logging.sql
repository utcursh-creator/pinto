-- SEC-10: the two existing broadcast triggers swallowed every exception with no
-- trace, masking programming errors / corruption. Keep the "never abort the
-- write" guarantee but log the failure so it is diagnosable.
create or replace function public.broadcast_delivery_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  _match_id uuid;
  _rec public.deliveries := coalesce(NEW, OLD);
begin
  select i.match_id into _match_id from public.innings i where i.id = _rec.innings_id;
  perform realtime.broadcast_changes(
    'match:' || _match_id::text, tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then
  raise warning 'broadcast_delivery_change failed: %', sqlerrm;
  return null;
end; $$;

create or replace function public.broadcast_dm_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare _rec public.dm_messages := coalesce(NEW, OLD);
begin
  perform realtime.broadcast_changes(
    'dm:' || _rec.thread_id::text, tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then
  raise warning 'broadcast_dm_message failed: %', sqlerrm;
  return null;
end; $$;
