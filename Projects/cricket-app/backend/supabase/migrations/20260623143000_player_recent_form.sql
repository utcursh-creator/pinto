-- player_recent_form(_player_key, _n): the player's last _n COMPLETE matches,
-- newest first, one collapsed batting + bowling line per match (summed across the
-- match's innings). Drives the "last 5" form strip. SECURITY DEFINER + anon-safe,
-- same completed-only policy as player_career_stats.
create or replace function public.player_recent_form(_player_key uuid, _n int default 5)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  _members uuid[];
  _result jsonb := '[]'::jsonb;
  m record; inn record; card jsonb; line jsonb;
  _runs int; _balls int; _out_flag boolean; _howout text;
  _wkts int; _conc int; _bb int;
begin
  select array_agg(member_id) into _members from public.v_player_key where player_key = _player_key;
  if _members is null then return '[]'::jsonb; end if;

  for m in
    select mt.id, mt.created_at
    from public.matches mt
    where mt.status = 'complete'
      and exists (select 1 from public.match_squad ms
                  where ms.match_id = mt.id and ms.team_member_id = any(_members))
    order by mt.created_at desc, mt.id desc
    limit greatest(_n, 0)
  loop
    _runs := 0; _balls := 0; _out_flag := false; _howout := null;
    _wkts := 0; _conc := 0; _bb := 0;
    for inn in select id from public.innings where match_id = m.id loop
      card := public.compute_innings_cards(inn.id);
      select value into line from jsonb_array_elements(card->'batting')
        where (value->>'member_id')::uuid = any(_members) limit 1;
      if line is not null then
        _runs := _runs + (line->>'runs')::int;
        _balls := _balls + (line->>'balls')::int;
        if (line->>'dismissed')::boolean then _out_flag := true; _howout := line->>'how_out'; end if;
      end if;
      select value into line from jsonb_array_elements(card->'bowling')
        where (value->>'member_id')::uuid = any(_members) limit 1;
      if line is not null then
        _wkts := _wkts + (line->>'wickets')::int;
        _conc := _conc + (line->>'runs_conceded')::int;
        _bb := _bb + (line->>'legal_balls')::int;
      end if;
    end loop;
    _result := _result || jsonb_build_object(
      'match_id', m.id,
      'bat',  jsonb_build_object('runs',_runs,'balls',_balls,'out',_out_flag,'how_out',_howout),
      'bowl', jsonb_build_object('wickets',_wkts,'runs_conceded',_conc,'balls',_bb)
    );
  end loop;
  return _result;
end; $$;
revoke all on function public.player_recent_form(uuid, int) from public;
grant execute on function public.player_recent_form(uuid, int) to anon, authenticated;
