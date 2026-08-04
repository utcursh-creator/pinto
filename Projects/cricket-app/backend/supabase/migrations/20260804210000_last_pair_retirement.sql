-- Whole-system review #2 (2026-07-28), finding 85: retire_batter accepted a
-- last-pair RETIRED HURT with no incoming batter, producing a state none of the
-- three folds can represent - a batter who has retired but is still the striker.

CREATE OR REPLACE FUNCTION public.retire_batter(_innings_id uuid, _retiring_batter_id uuid, _out boolean DEFAULT false, _incoming_batter_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  _match_id uuid; _state jsonb; _striker uuid; _non_striker uuid;
  _seq bigint; _id uuid; _wtype public.wicket_type;
begin
  select i.match_id into _match_id from public.innings i where i.id = _innings_id;
  if _match_id is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));

  _state := public.compute_innings_state(_innings_id);
  if _state->>'innings_status' <> 'in_progress' then
    raise exception 'the innings is over' using errcode = 'P0001';
  end if;
  _striker := (_state->>'striker_id')::uuid;
  _non_striker := (_state->>'non_striker_id')::uuid;
  if _retiring_batter_id <> _striker and _retiring_batter_id <> _non_striker then
    raise exception 'that batter is not at the crease' using errcode = 'P0001';
  end if;
  -- An incoming batter is required UNLESS this retirement is itself the last
  -- wicket - and only a RETIRED OUT can be a wicket at all.
  --
  -- The old test was `wickets_remaining >= 2`, copied from record_ball. There
  -- the relaxation is safe because the wicket ENDS the innings. A retired-hurt
  -- counts no wicket, so nothing ended: the fold saw 'retired_not_out' with a
  -- null incoming batter, counted no wicket (the all-out check never fired) and
  -- left the pair untouched - so a batter who had walked off stayed on strike,
  -- and every later ball's runs, balls faced, fours and sixes were credited to
  -- them. Permanently, because career stats bake from the cards
  -- (whole-system review #2, finding 85).
  if _incoming_batter_id is null
     and not (_out and coalesce((_state->>'wickets_remaining')::int, 99) <= 1) then
    raise exception 'an incoming batter is required (a retired hurt is not a wicket, so somebody must come in)' using errcode = 'P0001';
  end if;
  if _incoming_batter_id in (_striker, _non_striker) then
    raise exception 'the incoming batter is already at the crease' using errcode = 'P0001';
  end if;

  _wtype := case when _out then 'retired_out'::public.wicket_type else 'retired_not_out'::public.wicket_type end;
  select coalesce(max(seq),0) + 1 into _seq from public.deliveries where innings_id = _innings_id;

  insert into public.deliveries(innings_id, seq, event_kind, wicket_type,
                                dismissed_player_id, incoming_batter_id,
                                striker_id, non_striker_id)
  values (_innings_id, _seq, 'retirement', _wtype,
          _retiring_batter_id, _incoming_batter_id, _striker, _non_striker)
  returning id into _id;
  return _id;
end; $function$;
