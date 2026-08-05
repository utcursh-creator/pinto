-- Review #3 (MEDIUM), finding 15: no correction path can set the run-out
-- `crossed` flag, so a corrected run-out leaves the wrong batter on strike for
-- the rest of the innings.
--
-- A ball goes unrecorded (scorer distracted between overs). On it the
-- non-striker was run out and the batters HAD crossed. Inserting it from the
-- ball log wrote crossed = NULL, because insert_ball's signature had no
-- _crossed at all. compute_innings_state, compute_innings_cards and
-- restamp_innings_strike all test `coalesce(d.crossed,false)`, so all three
-- skipped the crossing swap in lockstep: every later run, ball faced, four and
-- six went to the wrong batter, and restamp stamped the wrong pair onto every
-- subsequent row of the ball log the scorer reads back. The only recovery was
-- the console's separate Swap-strike action, which nothing pointed them to.
--
-- edit_ball already takes _crossed - it was given one when review #2 stopped it
-- DESTROYING an existing value - so this is the last hole in the pair.
--
-- DROP first: `create or replace` with a new arity creates an OVERLOAD, not a
-- replacement, and two candidates make every PostgREST call ambiguous (300).
drop function if exists public.insert_ball(uuid, bigint, uuid, integer, integer,
  integer, integer, integer, integer, public.noball_secondary_kind,
  public.wicket_type, uuid, uuid, uuid);

create function public.insert_ball(
  _innings_id uuid,
  _after_seq bigint,
  _bowler_id uuid,
  _runs_off_bat integer default 0,
  _extra_wides integer default 0,
  _extra_no_ball_penalty integer default 0,
  _extra_byes integer default 0,
  _extra_leg_byes integer default 0,
  _extra_penalty integer default 0,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null,
  _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null,
  _fielder_id uuid default null,
  _crossed boolean default null)
returns uuid
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
  insert into public.deliveries(innings_id,seq,bowler_id,runs_off_bat,extra_wides,extra_no_ball_penalty,extra_byes,extra_leg_byes,extra_penalty,noball_secondary_kind,wicket_type,dismissed_player_id,incoming_batter_id,fielder_id,crossed,striker_id,non_striker_id)
  values (_innings_id,_after_seq+1,_bowler_id,_runs_off_bat,_extra_wides,_extra_no_ball_penalty,_extra_byes,_extra_leg_byes,_extra_penalty,_noball_secondary_kind,_wicket_type,_dismissed_player_id,_incoming_batter_id,_fielder_id,_crossed,_os,_ons)
  returning id into _id;
  perform public.restamp_innings_strike(_innings_id);
  perform set_config('pitch.suppress_delivery_broadcast', 'off', true);

  perform public.emit_delivery_broadcast(_innings_id);
  return _id;
end; $function$;

revoke all on function public.insert_ball(uuid, bigint, uuid, integer, integer,
  integer, integer, integer, integer, public.noball_secondary_kind,
  public.wicket_type, uuid, uuid, uuid, boolean) from public;
grant execute on function public.insert_ball(uuid, bigint, uuid, integer, integer,
  integer, integer, integer, integer, public.noball_secondary_kind,
  public.wicket_type, uuid, uuid, uuid, boolean) to authenticated;
