-- HIGH (penetration review 2026-07-07, completeness critic): a TIED knockout
-- permanently bricks the tournament. advance_playoffs demands a non-null
-- winner_team_id; a semifinal that finishes level is status='complete' with a
-- null winner, so the organizer sees both semis "Done", taps "Advance to final",
-- and gets a failure with nothing in the app able to reset, re-score or delete
-- the fixture. The tournament is stuck forever.
--
-- Real cricket breaks a tied knockout with a super over / bowl-out, and the
-- result of that is a decision, not a re-score. So: give the organizer an
-- explicit, audited way to record it.
create or replace function public.resolve_tied_fixture(
  _match_id uuid, _winner_team_id uuid, _note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare _a uuid; _b uuid; _st public.match_status; _winner uuid; _stage public.tournament_stage;
begin
  select tm.stage into _stage from public.tournament_matches tm where tm.match_id = _match_id;
  if _stage is null then
    raise exception 'that match is not a tournament fixture' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.tournament_matches tm
                  where tm.match_id = _match_id
                    and public.is_tournament_organizer(tm.tournament_id)) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if _stage = 'group' then
    raise exception 'a tied group match is a legitimate result - only knockouts need breaking'
      using errcode = 'P0001';
  end if;

  select team_a_id, team_b_id, status, (result->>'winner_team_id')::uuid
    into _a, _b, _st, _winner
  from public.matches where id = _match_id;
  if _a is null then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _st <> 'complete' then
    raise exception 'finish the match before breaking the tie' using errcode = 'P0001';
  end if;
  if _winner is not null then
    raise exception 'that match already has a winner' using errcode = 'P0001';
  end if;
  if _winner_team_id is distinct from _a and _winner_team_id is distinct from _b then
    raise exception 'the winner must be one of the two teams in this match'
      using errcode = 'P0001';
  end if;

  -- keep the tie on the record (NRR and the scorecard stay honest); the override
  -- only decides who progresses.
  update public.matches
     set result = result
                  || jsonb_build_object('winner_team_id', _winner_team_id,
                                        'margin_method', 'super_over',
                                        'tie_broken', true,
                                        'tie_break_note',
                                        coalesce(_note, 'Tie broken by the organizer'))
   where id = _match_id;
end; $$;
revoke all on function public.resolve_tied_fixture(uuid, uuid, text) from public;
grant execute on function public.resolve_tied_fixture(uuid, uuid, text) to authenticated;
