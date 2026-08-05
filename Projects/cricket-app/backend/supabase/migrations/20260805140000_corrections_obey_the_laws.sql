-- Review #2 finding 28, REOPENED by review #3 and confirmed by hand: the two
-- CORRECTION paths accept dismissals that cannot happen.
--
-- record_ball has always enforced the Laws - off a no-ball or a free hit only a
-- run out / obstructing / hit ball twice is possible; off a wide only a hit
-- wicket / obstructing / run out / stumped - and the scoring console mirrors the
-- same two lists in its wicket sheet. edit_ball and insert_ball never had them.
-- A scorer fixing "that was actually a no-ball" on a wicket ball produced a
-- batter bowled off a no-ball, and because compute_innings_cards feeds
-- player_career_stats, compute_match_potm (frozen into matches.potm) and
-- tournament_leaderboard, the impossible wicket became a permanent public
-- career record for a bowler who never took it.
--
-- I refuted this finding in the review-#2 ledger on the grounds that
-- "record_ball ALREADY validates both guards correctly". That is true and it is
-- beside the point: the finding was about correcting a ball, not recording one.
--
-- THE SHAPE OF THE FIX MATTERS. Three write paths had the rule copied into one
-- of them, so the other two drifted. The rule now lives in ONE function that all
-- three call. Adding a fourth write path without the guard is now a visible
-- omission rather than an invisible one.

-- Was the delivery at _seq bowled on a free hit?
--
-- This has to agree with the fold exactly. compute_innings_state sets free hit
-- on a no-ball and clears it on the next LEGAL delivery, so a free hit survives
-- intervening wides: the answer is "the most recent earlier delivery that was
-- either a no-ball or legal - was it a no-ball?".
create or replace function public.free_hit_at(_innings_id uuid, _seq bigint)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select coalesce((
    select d.extra_no_ball_penalty > 0
      from public.deliveries d
     where d.innings_id = _innings_id
       and d.seq < _seq
       and (d.extra_no_ball_penalty > 0 or d.is_legal)
     order by d.seq desc
     limit 1), false);
$function$;

-- The Laws, in one place.
create or replace function public.assert_legal_dismissal(
  _wicket_type public.wicket_type,
  _extra_wides int,
  _extra_no_ball_penalty int,
  _free_hit boolean default false
) returns void
language plpgsql
immutable
set search_path to 'public'
as $function$
begin
  if _wicket_type is null then return; end if;
  -- off a no-ball or a free hit the ball is not "in play" for the bowler
  if (coalesce(_free_hit, false) or coalesce(_extra_no_ball_penalty, 0) > 0)
     and _wicket_type not in ('run_out','obstructing','hit_ball_twice') then
    raise exception 'illegal dismissal on a no-ball/free-hit' using errcode = 'P0001';
  end if;
  -- a wide is not a ball the batter could have hit
  if coalesce(_extra_wides, 0) > 0
     and _wicket_type not in ('hit_wicket','obstructing','run_out','stumped') then
    raise exception 'illegal dismissal on a wide' using errcode = 'P0001';
  end if;
end; $function$;

revoke all on function public.free_hit_at(uuid, bigint) from public;
revoke all on function public.assert_legal_dismissal(public.wicket_type, int, int, boolean) from public;
grant execute on function public.free_hit_at(uuid, bigint) to authenticated;
grant execute on function public.assert_legal_dismissal(public.wicket_type, int, int, boolean) to authenticated;

-- ---------------------------------------------------------------- edit_ball
-- The guard runs on the MERGED row, not on the arguments: edit_ball is a
-- COALESCE patch, so "make this a no-ball" arrives with _wicket_type null and
-- the existing 'bowled' still on the row. Checking the arguments alone would
-- miss exactly the correction that started this.
create or replace function public.edit_ball(
  _delivery_id uuid, _runs_off_bat int default null, _extra_wides int default null,
  _extra_no_ball_penalty int default null, _extra_byes int default null,
  _extra_leg_byes int default null, _extra_penalty int default null,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null,
  _crossed boolean default null, _prevented_catch boolean default null,
  _is_overthrow boolean default null, _overthrow_crossed boolean default null,
  _wagon_x real default null, _wagon_y real default null, _wagon_zone smallint default null,
  _commentary_text text default null, _clear_wicket boolean default false,
  _clear_wagon boolean default false
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  _in uuid; _m uuid; _seq int; _old public.deliveries;
  _eff_wicket public.wicket_type; _eff_incoming uuid;
  _eff_wides int; _eff_noball int;
begin
  -- preamble preserved VERBATIM from 20260707130300_edit_ball_patch.sql: the
  -- event-kind refusal and the advisory lock are load-bearing, and rewriting a
  -- function from memory is how they get dropped.
  select * into _old from public.deliveries where id = _delivery_id;
  if _old.id is null then raise exception 'delivery not found' using errcode='P0001'; end if;
  _in := _old.innings_id; _seq := _old.seq;
  select match_id into _m from public.innings where id = _in;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  if _old.event_kind is not null then
    raise exception 'this is a match event, not a ball - undo it instead'
      using errcode='P0001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(_in::text, 0));

  -- the guard must see the EFFECTIVE post-patch values, not just what was sent
  _eff_wicket := case when _clear_wicket then null
                      else coalesce(_wicket_type, _old.wicket_type) end;
  _eff_incoming := case when _clear_wicket then null
                        else coalesce(_incoming_batter_id, _old.incoming_batter_id) end;
  _eff_wides  := coalesce(_extra_wides, _old.extra_wides);
  _eff_noball := coalesce(_extra_no_ball_penalty, _old.extra_no_ball_penalty);

  -- the Laws, on the row as it will be AFTER this edit
  perform public.assert_legal_dismissal(
    _eff_wicket, _eff_wides, _eff_noball, public.free_hit_at(_in, _seq));

  -- SCOR-2/5: a wicket edit mid-innings must name the incoming batter.
  perform public.correction_wicket_guard(_in, _seq, _eff_wicket, _eff_incoming, false);

  update public.deliveries set
    runs_off_bat          = coalesce(_runs_off_bat, runs_off_bat),
    extra_wides           = coalesce(_extra_wides, extra_wides),
    extra_no_ball_penalty = coalesce(_extra_no_ball_penalty, extra_no_ball_penalty),
    extra_byes            = coalesce(_extra_byes, extra_byes),
    extra_leg_byes        = coalesce(_extra_leg_byes, extra_leg_byes),
    extra_penalty         = coalesce(_extra_penalty, extra_penalty),
    noball_secondary_kind = coalesce(_noball_secondary_kind, noball_secondary_kind),
    wicket_type           = case when _clear_wicket then null
                                 else coalesce(_wicket_type, wicket_type) end,
    dismissed_player_id   = case when _clear_wicket then null
                                 else coalesce(_dismissed_player_id, dismissed_player_id) end,
    incoming_batter_id    = case when _clear_wicket then null
                                 else coalesce(_incoming_batter_id, incoming_batter_id) end,
    fielder_id            = case when _clear_wicket then null
                                 else coalesce(_fielder_id, fielder_id) end,
    crossed               = coalesce(_crossed, crossed),
    prevented_catch       = coalesce(_prevented_catch, prevented_catch),
    is_overthrow          = coalesce(_is_overthrow, is_overthrow),
    overthrow_crossed     = coalesce(_overthrow_crossed, overthrow_crossed),
    wagon_x               = case when _clear_wagon then null else coalesce(_wagon_x, wagon_x) end,
    wagon_y               = case when _clear_wagon then null else coalesce(_wagon_y, wagon_y) end,
    wagon_zone            = case when _clear_wagon then null else coalesce(_wagon_zone, wagon_zone) end,
    commentary_text       = coalesce(_commentary_text, commentary_text),
    updated_at            = now()
  where id = _delivery_id;

  perform public.restamp_innings_strike(_in);
end; $function$;

-- -------------------------------------------------------------- insert_ball
-- The inserted ball lands at _after_seq + 1, so its free-hit context is decided
-- by the deliveries at or before _after_seq - which is exactly what free_hit_at
-- asks, and it has to be asked BEFORE the renumbering shifts everything.
create or replace function public.insert_ball(
  _innings_id uuid, _after_seq bigint, _bowler_id uuid, _runs_off_bat int default 0,
  _extra_wides int default 0, _extra_no_ball_penalty int default 0,
  _extra_byes int default 0, _extra_leg_byes int default 0, _extra_penalty int default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _m uuid; _id uuid; _os uuid; _ons uuid; _shifting boolean;
begin
  select match_id into _m from public.innings where id = _innings_id;
  if _m is null or not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_innings_id::text, 0));

  -- the Laws, on the ball about to be inserted
  perform public.assert_legal_dismissal(
    _wicket_type, _extra_wides, _extra_no_ball_penalty,
    public.free_hit_at(_innings_id, _after_seq + 1));

  -- SCOR-2/5: an inserted wicket with balls after it must name the incoming batter.
  select exists (select 1 from public.deliveries
                 where innings_id = _innings_id and seq > _after_seq) into _shifting;
  perform public.correction_wicket_guard(_innings_id, _after_seq::int, _wicket_type, _incoming_batter_id, _shifting);
  select opening_striker_id, opening_non_striker_id into _os, _ons from public.innings where id = _innings_id;

  perform set_config('pitch.suppress_delivery_broadcast', 'on', true);
  update public.deliveries set seq = -(seq + 1) where innings_id = _innings_id and seq > _after_seq;
  update public.deliveries set seq = -seq where innings_id = _innings_id and seq < 0;
  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,striker_id,non_striker_id)
  values (_innings_id,_after_seq+1,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_os,_ons)
  returning id into _id;
  perform public.restamp_innings_strike(_innings_id);
  perform set_config('pitch.suppress_delivery_broadcast', 'off', true);

  perform public.emit_delivery_broadcast(_innings_id);
  return _id;
end; $function$;
