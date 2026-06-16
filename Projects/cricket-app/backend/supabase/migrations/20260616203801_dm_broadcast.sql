create or replace function public.broadcast_dm_message()
returns trigger language plpgsql security definer set search_path = '' as $$
declare _rec public.dm_messages := coalesce(NEW, OLD);
begin
  perform realtime.broadcast_changes('dm:' || _rec.thread_id::text, tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then return null;
end; $$;

create trigger dm_messages_broadcast
  after insert on public.dm_messages
  for each row execute function public.broadcast_dm_message();

create policy "dm_broadcast_receive" on realtime.messages for select to authenticated
  using (realtime.messages.extension = 'broadcast'
         and realtime.topic() like 'dm:%'
         and public.is_thread_participant((split_part(realtime.topic(), ':', 2))::uuid));
