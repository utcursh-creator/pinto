-- HIGH (penetration review 2026-07-07, console-still-records-retirements-as-balls):
-- fold v14 made retirements non-ball EVENT rows precisely because recording them
-- as deliveries corrupts every count. But record_ball still ACCEPTED
-- 'retired_out' / 'timed_out' / 'retired_not_out', and the console's Wicket pad
-- still offered them - one tap from the new Retire action, doing exactly the
-- corruption the event-row work removed: a ball is consumed, the over advances,
-- the bowler is charged, and (worse) the fold dismisses the STRIKER rather than
-- the batter the scorer named.
--
-- Server-side backstop so the corruption stops before any APK ships. The UI fix
-- is separate; this makes the bad state unrepresentable.
create or replace function public.record_ball(
  _innings_id uuid, _bowler_id uuid,
  _runs_off_bat int default 0, _extra_wides int default 0, _extra_no_ball_penalty int default 0,
  _extra_byes int default 0, _extra_leg_byes int default 0, _extra_penalty int default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null,
  _crossed boolean default null, _prevented_catch boolean default null,
  _is_overthrow boolean default false, _overthrow_crossed boolean default null,
  _wagon_x real default null, _wagon_y real default null, _wagon_zone smallint default null,
  _commentary_text text default null, _expected_last_seq bigint default null
) returns table(delivery_id uuid, wagon_applicable boolean)
language plpgsql security definer set search_path = public as $$
declare
  _match_id uuid; _bpo int; _allow_consec boolean; _state jsonb;
  _striker uuid; _non_striker uuid; _free_hit boolean;
  _seq bigint; _legal_count int; _last_bowler uuid; _last_legal boolean; _id uuid;
  _cap_overs int; _bowler_legal int; _cur_last bigint;
begin
  -- a retirement / timed-out is an EVENT between balls, never a delivery
  if _wicket_type in ('retired_out','retired_not_out','timed_out') then
    raise exception 'a retirement is not a ball - use retire_batter' using errcode = 'P0001';
  end if;

  select i.match_id, coalesce(m.balls_per_over,6), coalesce((m.rules->>'allow_consecutive_overs')::boolean, false),
         (m.rules->>'max_overs_per_bowler')::int
    into _match_id, _bpo, _allow_consec, _cap_overs
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;
  if _match_id is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));

  -- SCOR-24: reject an append computed against a state another device replaced
  select coalesce(max(seq),0) into _cur_last from public.deliveries where innings_id = _innings_id;
  if _expected_last_seq is not null and _cur_last <> _expected_last_seq then
    raise exception 'the innings changed on another device - refresh before recording' using errcode = 'P0001';
  end if;

  _state := public.compute_innings_state(_innings_id);
  _striker := (_state->>'striker_id')::uuid;
  _non_striker := (_state->>'non_striker_id')::uuid;
  _free_hit := coalesce((_state->>'free_hit_active')::boolean, false);

  if _wicket_type is not null then
    if (_free_hit or _extra_no_ball_penalty > 0) and _wicket_type not in ('run_out','obstructing','hit_ball_twice') then
      raise exception 'illegal dismissal on a no-ball/free-hit' using errcode = 'P0001';
    end if;
    if _extra_wides > 0 and _wicket_type not in ('hit_wicket','obstructing','run_out','stumped') then
      raise exception 'illegal dismissal on a wide' using errcode = 'P0001';
    end if;
  end if;

  -- SCOR-2: a batter-removing dismissal needs an incoming batter, unless it is the
  -- final wicket (all out after it).
  if _wicket_type is not null
     and _incoming_batter_id is null
     and coalesce((_state->>'wickets_remaining')::int, 99) >= 2 then
    raise exception 'an incoming batter is required (this is not the last wicket)' using errcode = 'P0001';
  end if;

  select count(*) filter (where is_legal) into _legal_count from public.deliveries where innings_id = _innings_id;
  if _legal_count > 0 and (_legal_count % _bpo) = 0 then
    if not _allow_consec then
      select bowler_id, is_legal into _last_bowler, _last_legal
        from public.deliveries where innings_id = _innings_id and event_kind is null
        order by seq desc limit 1;
      if _last_legal and _last_bowler = _bowler_id then
        raise exception 'bowler cannot bowl consecutive overs' using errcode = 'P0001';
      end if;
    end if;
    -- SCOR-15: a bowler at their quota cannot START another over.
    if _cap_overs is not null then
      select count(*) into _bowler_legal from public.deliveries
        where innings_id = _innings_id and bowler_id = _bowler_id and is_legal;
      if _bowler_legal >= _cap_overs * _bpo then
        raise exception 'bowler has reached the % over limit', _cap_overs using errcode = 'P0001';
      end if;
    end if;
  end if;

  select coalesce(max(seq),0) + 1 into _seq from public.deliveries where innings_id = _innings_id;

  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,crossed,prevented_catch,is_overthrow,overthrow_crossed,wagon_x,wagon_y,wagon_zone,commentary_text,striker_id,non_striker_id)
  values (_innings_id,_seq,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_crossed,_prevented_catch,_is_overthrow,_overthrow_crossed,_wagon_x,_wagon_y,_wagon_zone,_commentary_text,_striker,_non_striker)
  returning id into _id;

  delivery_id := _id;
  wagon_applicable :=
        _extra_wides = 0 and _extra_byes = 0 and _extra_leg_byes = 0
    and (_noball_secondary_kind is null or _noball_secondary_kind = 'off_bat')
    and (_wicket_type is null or _wicket_type in ('caught','run_out'));
  return next;
end; $$;

-- and make it unrepresentable at the schema level for NEW rows: a retirement
-- wicket type may only ever appear on an event row.
alter table public.deliveries add constraint deliveries_retirement_is_event check (
  wicket_type is null
  or wicket_type not in ('retired_out','retired_not_out','timed_out')
  or event_kind is not null
) not valid;
