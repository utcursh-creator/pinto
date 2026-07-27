-- HIGH (penetration review 2026-07-07, found by 3 fronts): edit_ball was a FULL
-- COLUMN OVERWRITE - every omitted parameter reset its column to 0/null. The
-- corrections UI can neither read nor resend extra_penalty, crossed,
-- is_overthrow, overthrow_crossed or the wagon-wheel shot, so EVERY correction
-- a scorer makes silently destroys them. The `crossed` loss is the worst: it
-- re-stamps strike for the remainder of the innings, so a single "fix the runs"
-- edit can hand the rest of the innings to the wrong batter.
--
-- Fix: PATCH semantics. NULL now means "leave this column alone"; the caller
-- sends only what it is actually editing. Explicit clears are opt-in flags.
-- This deliberately makes the EXISTING client safe with no app update: the app
-- sends runs/wides/no-ball/byes/leg-byes (which it does control, and 0 still
-- means 0) and omits the rest, which is now preserved instead of wiped.
--
-- New parameters -> the old signature must go, or PostgREST sees an ambiguous
-- overload.
drop function public.edit_ball(uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text);

create function public.edit_ball(
  _delivery_id uuid,
  _runs_off_bat int default null, _extra_wides int default null,
  _extra_no_ball_penalty int default null, _extra_byes int default null,
  _extra_leg_byes int default null, _extra_penalty int default null,
  _noball_secondary_kind public.noball_secondary_kind default null,
  _wicket_type public.wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null,
  _crossed boolean default null, _prevented_catch boolean default null,
  _is_overthrow boolean default null, _overthrow_crossed boolean default null,
  _wagon_x real default null, _wagon_y real default null, _wagon_zone smallint default null,
  _commentary_text text default null,
  _clear_wicket boolean default false, _clear_wagon boolean default false
) returns void language plpgsql security definer set search_path = public as $$
declare
  _in uuid; _m uuid; _seq int; _old public.deliveries;
  _eff_wicket public.wicket_type; _eff_incoming uuid;
begin
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

  -- the guard must see the EFFECTIVE post-patch wicket, not just what was sent
  _eff_wicket  := case when _clear_wicket then null
                       else coalesce(_wicket_type, _old.wicket_type) end;
  _eff_incoming := case when _clear_wicket then null
                        else coalesce(_incoming_batter_id, _old.incoming_batter_id) end;
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
end; $$;
revoke all on function public.edit_ball(uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text,boolean,boolean) from public;
grant execute on function public.edit_ball(uuid,int,int,int,int,int,int,public.noball_secondary_kind,public.wicket_type,uuid,uuid,uuid,boolean,boolean,boolean,boolean,real,real,smallint,text,boolean,boolean) to authenticated;
