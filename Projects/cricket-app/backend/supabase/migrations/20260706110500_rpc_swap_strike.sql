-- SCOR-16: manual strike correction as an event row. For the rare real-world
-- cases the derivation cannot know (umpire-directed end change, scorer noticed
-- the batters at the wrong ends) - undoable and correction-safe like any ball.
create or replace function public.swap_strike(_innings_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  _match_id uuid; _state jsonb; _seq bigint; _id uuid;
begin
  select i.match_id into _match_id from public.innings i where i.id = _innings_id;
  if _match_id is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));

  _state := public.compute_innings_state(_innings_id);
  if _state->>'innings_status' <> 'in_progress' then
    raise exception 'the innings is over' using errcode = 'P0001';
  end if;

  select coalesce(max(seq),0) + 1 into _seq from public.deliveries where innings_id = _innings_id;
  insert into public.deliveries(innings_id, seq, event_kind, striker_id, non_striker_id)
  values (_innings_id, _seq, 'strike_swap',
          (_state->>'striker_id')::uuid, (_state->>'non_striker_id')::uuid)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.swap_strike(uuid) from public;
grant execute on function public.swap_strike(uuid) to authenticated;
