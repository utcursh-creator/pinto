-- SEC-6 / MTCH-3: harden set_match_result.
--  * a winner_team_id, when the result type needs one, MUST be one of the two
--    teams in THIS match (reject a forged/foreign winner id).
--  * no-winner result types (tie / no_result / abandoned) force winner -> null.
--  * refuse to overwrite a match that already has a final result (terminal
--    status), so a completed scorecard cannot be silently rewritten.
create or replace function public.set_match_result(
  _match_id uuid, _result_type public.result_type, _winner_team_id uuid default null, _note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  _a uuid; _b uuid; _st public.match_status;
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;

  select team_a_id, team_b_id, status into _a, _b, _st
    from public.matches where id = _match_id;
  if not found then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _st in ('complete', 'abandoned') then
    raise exception 'this match already has a final result' using errcode = 'P0001';
  end if;

  if _result_type in ('tie', 'no_result', 'abandoned') then
    _winner_team_id := null;                       -- these have no winner
  else
    if _winner_team_id is null then
      raise exception 'a winner is required for a % result', _result_type using errcode = 'P0001';
    end if;
    if _winner_team_id <> _a and _winner_team_id <> _b then
      raise exception 'the winner must be one of the two teams in this match' using errcode = 'P0001';
    end if;
  end if;

  update public.matches set
    result = jsonb_build_object('result_type', _result_type, 'winner_team_id', _winner_team_id,
                                'note', _note, 'margin_method', 'normal'),
    status = case when _result_type = 'abandoned' then 'abandoned'::public.match_status
                  else 'complete'::public.match_status end
  where id = _match_id;
end; $$;
revoke all on function public.set_match_result(uuid, public.result_type, uuid, text) from public;
grant execute on function public.set_match_result(uuid, public.result_type, uuid, text) to authenticated;
