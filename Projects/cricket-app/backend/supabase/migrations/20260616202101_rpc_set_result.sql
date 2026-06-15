create or replace function public.set_match_result(
  _match_id uuid, _result_type public.result_type, _winner_team_id uuid default null, _note text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  update public.matches set
    result = jsonb_build_object('result_type', _result_type, 'winner_team_id', _winner_team_id,
                                'note', _note, 'margin_method', 'normal'),
    status = case when _result_type = 'abandoned' then 'abandoned'::public.match_status
                  else 'complete'::public.match_status end
  where id = _match_id;
end; $$;
revoke all on function public.set_match_result(uuid, public.result_type, uuid, text) from public;
grant execute on function public.set_match_result(uuid, public.result_type, uuid, text) to authenticated;
