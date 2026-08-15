-- Journey map C1 (2026-08-05): a dot ball must not open the wagon-wheel sheet.
-- See Projects/cricket-app/2026-08-05-user-journey-map.md section 3.
CREATE OR REPLACE FUNCTION public.record_ball(_innings_id uuid, _bowler_id uuid, _runs_off_bat integer DEFAULT 0, _extra_wides integer DEFAULT 0, _extra_no_ball_penalty integer DEFAULT 0, _extra_byes integer DEFAULT 0, _extra_leg_byes integer DEFAULT 0, _extra_penalty integer DEFAULT 0, _noball_secondary_kind noball_secondary_kind DEFAULT NULL::noball_secondary_kind, _wicket_type wicket_type DEFAULT NULL::wicket_type, _dismissed_player_id uuid DEFAULT NULL::uuid, _incoming_batter_id uuid DEFAULT NULL::uuid, _fielder_id uuid DEFAULT NULL::uuid, _crossed boolean DEFAULT NULL::boolean, _prevented_catch boolean DEFAULT NULL::boolean, _is_overthrow boolean DEFAULT false, _overthrow_crossed boolean DEFAULT NULL::boolean, _wagon_x real DEFAULT NULL::real, _wagon_y real DEFAULT NULL::real, _wagon_zone smallint DEFAULT NULL::smallint, _commentary_text text DEFAULT NULL::text, _expected_last_seq bigint DEFAULT NULL::bigint)
 RETURNS TABLE(delivery_id uuid, wagon_applicable boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  _match_id uuid; _bpo int; _allow_consec boolean; _state jsonb;
  _striker uuid; _non_striker uuid; _free_hit boolean;
  _seq bigint; _legal_count int; _last_bowler uuid; _last_legal boolean; _id uuid;
  _cap_overs int; _bowler_legal int; _cur_last bigint;
begin
  if _wicket_type in ('retired_out','retired_not_out','timed_out') then
    raise exception 'a retirement is not a ball - use retire_batter' using errcode = 'P0001';
  end if;

  select i.match_id, coalesce(m.balls_per_over,6), coalesce((m.rules->>'allow_consecutive_overs')::boolean, false)
    into _match_id, _bpo, _allow_consec
  from public.innings i join public.matches m on m.id = i.match_id where i.id = _innings_id;
  if _match_id is null then raise exception 'innings not found' using errcode = 'P0001'; end if;
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  _cap_overs := public._bowler_over_cap(_innings_id);

  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));

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
  -- Journey map C1: the scorer records ~120 deliveries standing at the
  -- boundary, and a DOT BALL is the most common outcome in the game. This never
  -- asked whether any runs were actually scored, so a dot came back applicable
  -- and the console opened "Where did 0 run(s) go?" on the majority of
  -- deliveries. The old journeys hid it behind a helper that dismissed the
  -- sheet after every tap.
  --
  -- Placement means something for runs off the bat, and for a CATCH (where the
  -- fielder took it) even when no runs were scored. It means nothing for a ball
  -- that went nowhere.
  wagon_applicable :=
        _extra_wides = 0 and _extra_byes = 0 and _extra_leg_byes = 0
    and (_noball_secondary_kind is null or _noball_secondary_kind = 'off_bat')
    and (_wicket_type is null or _wicket_type in ('caught','run_out'))
    -- IS NOT DISTINCT FROM, not '=': with no wicket the plain comparison is
    -- NULL, so `false or NULL` made wagon_applicable NULL rather than false and
    -- the console treated it as a prompt anyway. Caught by the test on the
    -- first run.
    and (_runs_off_bat > 0 or _wicket_type is not distinct from 'caught');
  return next;
end; $function$


;
