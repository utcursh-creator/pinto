-- Whole-system review #2 (2026-07-28), finding 61: matches.status is stuck at
-- 'innings_break' if a correction reopens the first innings.
--
-- The first innings ends, the console writes status = 'innings_break'. The
-- scorer then opens the Ball log - still reachable from the app bar - and
-- deletes the wrong final wicket. The fold re-computes to in_progress, the run
-- pad comes back and scoring resumes. But nothing writes the status back:
-- mark_innings_break only fires on 'live', and 'innings_break' -> 'live'
-- happens only inside start_innings.
--
-- So for the rest of that innings the viewer shows no LIVE badge, the
-- Watch-live list labels the game "innings break", and the Matches tile says
-- "Innings break" - while balls are being recorded.
--
-- Deliberately NOT a blind `set status = 'live'`. The RPC asks the FOLD whether
-- the innings really is in progress, so a scorer cannot use it to drag a
-- completed or abandoned match back to live. It is idempotent and safe to call
-- whenever the console notices the innings is open again.
create or replace function public.resume_from_innings_break(_match_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _in uuid; _status text;
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  -- the latest innings of this match
  select id into _in from public.innings
   where match_id = _match_id
   order by innings_number desc limit 1;
  if _in is null then return; end if;

  select public.compute_innings_state(_in)->>'innings_status' into _status;
  if _status is distinct from 'in_progress' then return; end if;

  update public.matches set status = 'live'
   where id = _match_id and status = 'innings_break';
end; $function$;

revoke all on function public.resume_from_innings_break(uuid) from public;
grant execute on function public.resume_from_innings_break(uuid) to authenticated;
