create or replace function public.broadcast_delivery_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  _match_id uuid;
  _rec public.deliveries := coalesce(NEW, OLD);
begin
  select i.match_id into _match_id from public.innings i where i.id = _rec.innings_id;
  perform realtime.broadcast_changes(
    'match:' || _match_id::text,  -- topic
    tg_op,                        -- event
    tg_op,                        -- operation
    tg_table_name,                -- table
    tg_table_schema,              -- schema
    NEW,                          -- new record
    OLD                           -- old record
  );
  return null;
exception when others then
  return null;  -- never abort the write on a broadcast failure
end;
$$;

create trigger deliveries_broadcast
  after insert or update or delete on public.deliveries
  for each row execute function public.broadcast_delivery_change();

-- Public live viewing: any viewer (incl. logged-out) may RECEIVE a match's broadcast.
-- Deliberate per the spec's public-read decision (CricHeroes-style login-free live scores).
-- No INSERT policy on realtime.messages: clients are read-only; the SECURITY DEFINER trigger writes.
create policy "match_broadcast_receive" on realtime.messages
  for select to authenticated, anon
  using (realtime.messages.extension = 'broadcast' and realtime.topic() like 'match:%');
