-- Review #3: re-entering setup on an already-live match rewrites its toss.
--
-- The scorer's own Matches tile still says "Setup - not started" for a game four
-- overs old (nothing invalidated myMatchesProvider when it went live - fixed on
-- the client in the same commit), so the only menu item is "Resume setup". That
-- walks back to a BLANK toss form, and _start awaits set_toss FIRST. Each RPC is
-- its own transaction, so the toss write COMMITS; the start_innings that follows
-- violates the one-innings-per-number unique key and throws, and the screen says
-- "Could not start the match" - implying nothing happened. The public,
-- login-free /watch/<id> Info tab now names the wrong toss winner for a match
-- being played. Reproduced by hand on the live database.
--
-- A toss is decided BEFORE play. Once an innings exists it is part of the
-- record - so the guard keys on the INNINGS, not on matches.status: status can
-- be dragged back to 'live' by a correction (resume_from_innings_break), and the
-- question here is only ever "has a ball been possible yet".
--
-- Correcting a mis-tapped toss DURING setup is still free, which is the whole
-- reason this is not simply "set it once".
-- NOTE the parameter type: the original is `public.toss_decision`, and writing
-- `text` here does not replace it - `create or replace` with a different
-- signature makes an OVERLOAD, which is ambiguous to PostgREST and was already
-- a documented trap in this project. Drop the stray one and keep the enum.
drop function if exists public.set_toss(uuid, uuid, text);

create or replace function public.set_toss(
  _match_id uuid, _winner_team_id uuid, _decision public.toss_decision
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _a uuid; _b uuid; _st public.match_status;
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  select team_a_id, team_b_id, status into _a, _b, _st
    from public.matches where id = _match_id;
  if _a is null then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _st in ('complete','abandoned') then
    raise exception 'this match already finished' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.innings i where i.match_id = _match_id) then
    raise exception 'the toss cannot be changed once play has started'
      using errcode = 'P0001';
  end if;
  if _winner_team_id is distinct from _a and _winner_team_id is distinct from _b then
    raise exception 'the toss winner must be one of the two teams in this match'
      using errcode = 'P0001';
  end if;
  update public.matches
     set toss_winner_id = _winner_team_id, toss_decision = _decision
   where id = _match_id;
end; $function$;
