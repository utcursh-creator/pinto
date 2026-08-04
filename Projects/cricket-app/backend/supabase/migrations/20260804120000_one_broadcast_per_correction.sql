-- Whole-system review #2 (2026-07-28): a correction fans out one realtime
-- broadcast PER SHIFTED DELIVERY.
--
-- insert_ball renumbers every delivery after the insertion point, and it does
-- so in two passes - negate, then restore - to dodge the unique index on
-- (innings_id, seq). Each pass is one UPDATE per row, and the AFTER ... FOR
-- EACH ROW broadcast trigger fires on every one of them. restamp_innings_strike
-- then rewrites the strikers, firing again.
--
-- Measured on a 30-ball innings (local stack, counting realtime.messages):
--   an ordinary record_ball .....  1 broadcast   <- correct
--   delete_ball at seq 3 ........ 15 broadcasts
--   insert_ball after seq 2 ..... 71 broadcasts
--
-- On a real 20-over innings correcting an early ball is several hundred. Every
-- one of those messages makes every connected viewer re-fold the ENTIRE innings
-- (compute_innings_state over all deliveries), so a single tap of "insert the
-- ball I missed" costs each watching phone hundreds of full re-folds, and the
-- cost grows with both the innings length and the audience.
--
-- The renumbering is bookkeeping. It is not news. The viewer re-folds from
-- scratch on any message, so ONE message at the end carries exactly as much
-- information as the 71 did.

-- 1. The trigger learns to stay quiet while an RPC is mid-shuffle.
create or replace function public.broadcast_delivery_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  _match_id uuid;
  _rec public.deliveries := coalesce(NEW, OLD);
begin
  -- current_setting(..., true) returns NULL when the GUC was never set, and
  -- NULL here must mean "broadcast normally" - so coalesce rather than compare
  -- against NULL. (Third time this codebase has been bitten by a NULL quietly
  -- disabling a guard; here the safe default is the loud one.)
  if coalesce(current_setting('pitch.suppress_delivery_broadcast', true), 'off')
       = 'on' then
    return null;
  end if;
  select i.match_id into _match_id from public.innings i where i.id = _rec.innings_id;
  perform realtime.broadcast_changes(
    'match:' || _match_id::text, tg_op, tg_op, tg_table_name, tg_table_schema, NEW, OLD);
  return null;
exception when others then
  raise warning 'broadcast_delivery_change failed: %', sqlerrm;
  return null;
end; $function$;

-- 2. The one message a correction is actually worth.
--
-- The payload is deliberately empty: the viewer's handler is
-- `callback: (_) => _refold()` and re-reads the whole innings, so naming any
-- single delivery would be arbitrary and misleading. 'UPDATE' is one of the
-- three events the viewer subscribes to.
create or replace function public.emit_delivery_broadcast(_innings_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare _match_id uuid;
begin
  select i.match_id into _match_id from public.innings i where i.id = _innings_id;
  if _match_id is null then return; end if;
  perform realtime.broadcast_changes(
    'match:' || _match_id::text, 'UPDATE', 'UPDATE', 'deliveries', 'public',
    null::public.deliveries, null::public.deliveries);
exception when others then
  raise warning 'emit_delivery_broadcast failed: %', sqlerrm;
end; $function$;

revoke all on function public.emit_delivery_broadcast(uuid) from public, anon, authenticated;

-- 3. Both correction RPCs go quiet, then say one thing.
--
-- set_config(..., is_local => true) scopes the flag to THIS transaction, so it
-- cannot leak into another statement on a pooled connection and it unwinds on
-- its own if the RPC raises partway through.
create or replace function public.insert_ball(
  _innings_id uuid, _after_seq bigint, _bowler_id uuid,
  _runs_off_bat integer default 0, _extra_wides integer default 0,
  _extra_no_ball_penalty integer default 0, _extra_byes integer default 0,
  _extra_leg_byes integer default 0, _extra_penalty integer default 0,
  _noball_secondary_kind noball_secondary_kind default null,
  _wicket_type wicket_type default null, _dismissed_player_id uuid default null,
  _incoming_batter_id uuid default null, _fielder_id uuid default null)
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

create or replace function public.delete_ball(_delivery_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _in uuid; _m uuid;
begin
  select innings_id into _in from public.deliveries where id = _delivery_id;
  if _in is null then raise exception 'delivery not found' using errcode='P0001'; end if;
  select match_id into _m from public.innings where id = _in;
  if not public.is_match_scorer(_m) then raise exception 'not authorized' using errcode='P0001'; end if;
  perform pg_advisory_xact_lock(hashtextextended(_in::text, 0));

  perform set_config('pitch.suppress_delivery_broadcast', 'on', true);
  delete from public.deliveries where id = _delivery_id;
  perform public.restamp_innings_strike(_in);
  perform set_config('pitch.suppress_delivery_broadcast', 'off', true);

  perform public.emit_delivery_broadcast(_in);
end; $function$;
