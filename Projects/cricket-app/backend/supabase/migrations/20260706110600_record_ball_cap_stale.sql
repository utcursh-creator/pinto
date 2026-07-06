-- SCOR-15 + SCOR-24: record_ball v3.
--  * max-overs-per-bowler cap, enforced when a bowler would START a new over.
--    Read from rules.max_overs_per_bowler; matches without the rule (all
--    pre-existing data + fixtures) stay uncapped. The app stamps the rule
--    (default ceil(overs/5), T20 -> 4) into every match it creates.
--  * optimistic-concurrency fence: the scorer passes the last_seq it folded
--    (fold v14 returns it); a stale device's append is rejected instead of
--    silently interleaving with another scorer's corrections.
--  * both bowler guards ignore v14 event rows (they carry no bowler).
-- New parameter -> new signature: drop the old function first (avoid overload
-- ambiguity through PostgREST).
drop function public.record_ball(uuid,uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text);

create function public.record_ball(
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
  -- final wicket (all out after it). Runs AFTER the dismissal-legality checks so an
  -- illegal dismissal is rejected for its own reason first. Otherwise the fold
  -- leaves the dismissed batter at the crease, scoring later runs/balls.
  if _wicket_type is not null and _wicket_type <> 'retired_not_out'
     and _incoming_batter_id is null
     and coalesce((_state->>'wickets_remaining')::int, 99) >= 2 then
    raise exception 'an incoming batter is required (this is not the last wicket)' using errcode = 'P0001';
  end if;

  select count(*) filter (where is_legal) into _legal_count from public.deliveries where innings_id = _innings_id;
  if _legal_count > 0 and (_legal_count % _bpo) = 0 then
    -- Consecutive-over guard: only when this is genuinely the first ball of a new
    -- over, i.e. the previous delivery was the over-completing LEGAL ball. If the
    -- new over already has a delivery (e.g. it opened with a wide), the same
    -- bowler is mid-over and must be allowed to continue. Event rows carry no
    -- bowler and do not break the over boundary.
    if not _allow_consec then
      select bowler_id, is_legal into _last_bowler, _last_legal
        from public.deliveries where innings_id = _innings_id and event_kind is null
        order by seq desc limit 1;
      if _last_legal and _last_bowler = _bowler_id then
        raise exception 'bowler cannot bowl consecutive overs' using errcode = 'P0001';
      end if;
    end if;
    -- SCOR-15: a bowler at their quota cannot START another over (finishing the
    -- current one is always allowed - their count only completes at its end).
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

  -- wagon_applicable: did the striker make a directional bat shot on this ball?
  delivery_id := _id;
  wagon_applicable :=
        _extra_wides = 0 and _extra_byes = 0 and _extra_leg_byes = 0
    and (_noball_secondary_kind is null or _noball_secondary_kind = 'off_bat')
    and (_wicket_type is null or _wicket_type in ('caught','run_out'));
  return next;
end; $$;
revoke all on function public.record_ball(uuid,uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text,bigint) from public;
grant execute on function public.record_ball(uuid,uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text,bigint) to authenticated;
