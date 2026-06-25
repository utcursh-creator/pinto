-- player_career_stats(_player_key): career batting / bowling / fielding for a
-- player, derived by RE-FOLDING each innings via compute_innings_cards (the only
-- correct source - a flat deliveries view mis-attributes dismissals and drifts
-- after corrections). SECURITY DEFINER + search_path='' + fully-qualified;
-- granted to anon + authenticated; the completed-status filter is baked in so an
-- anon caller can never reach setup/live data (mirrors public_profile_minimal).
--
-- Status policy: averages/aggregates fold COMPLETE matches only; matches-played
-- (Mat) counts complete + abandoned (via v_player_matches). retired_out counts
-- as a dismissal (the fold treats every wicket_type except retired_not_out as a
-- dismissal). Undefined ratios return null -> the client renders '-'.
create or replace function public.player_career_stats(_player_key uuid)
returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  _members uuid[];
  _mat int := 0;
  -- batting accumulators
  _b_inns int := 0; _b_runs int := 0; _b_balls int := 0; _b_fours int := 0; _b_sixes int := 0;
  _b_outs int := 0; _b_hs int := 0; _b_hs_notout boolean := false; _b_50 int := 0; _b_100 int := 0; _b_ducks int := 0;
  -- bowling accumulators
  _w_inns int := 0; _w_balls int := 0; _w_runs int := 0; _w_wkts int := 0; _w_maidens int := 0;
  _w_bbi_w int := -1; _w_bbi_r int := 0; _w_4w int := 0; _w_5w int := 0;
  -- fielding accumulators
  _f_ct int := 0; _f_ro int := 0; _f_st int := 0;
  -- per-innings scratch
  _i_runs int; _i_balls int; _i_fours int; _i_sixes int; _i_out boolean;
  _i_legal int; _i_conc int; _i_wkts int; _i_maid int; _i_wd int; _i_nb int;
  card jsonb; line jsonb; inn record;
  _bat_avg numeric; _bat_sr numeric; _bowl_avg numeric; _bowl_econ numeric; _bowl_sr numeric;
begin
  select array_agg(member_id) into _members from public.v_player_key where player_key = _player_key;
  if _members is null then _members := array[]::uuid[]; end if;

  select count(distinct match_id) into _mat from public.v_player_matches where player_key = _player_key;

  for inn in
    select i.id as innings_id
    from public.innings i
    join public.matches m on m.id = i.match_id
    where m.status = 'complete'
      and exists (select 1 from public.match_squad ms
                  where ms.match_id = m.id and ms.team_member_id = any(_members))
    order by i.id
  loop
    card := public.compute_innings_cards(inn.innings_id);

    -- batting
    select value into line from jsonb_array_elements(card->'batting')
      where (value->>'member_id')::uuid = any(_members) limit 1;
    if line is not null then
      _i_runs := (line->>'runs')::int; _i_balls := (line->>'balls')::int;
      _i_fours := (line->>'fours')::int; _i_sixes := (line->>'sixes')::int;
      _i_out := (line->>'dismissed')::boolean;
      if _i_balls > 0 or _i_out then               -- an innings batted: faced a ball OR was dismissed
        _b_inns := _b_inns + 1;
        _b_runs := _b_runs + _i_runs; _b_balls := _b_balls + _i_balls;
        _b_fours := _b_fours + _i_fours; _b_sixes := _b_sixes + _i_sixes;
        if _i_out then _b_outs := _b_outs + 1; end if;
        if (_i_runs > _b_hs) or (_i_runs = _b_hs and (not _i_out) and (not _b_hs_notout)) then
          _b_hs := _i_runs; _b_hs_notout := (not _i_out);
        end if;
        if _i_runs >= 100 then _b_100 := _b_100 + 1;
        elsif _i_runs >= 50 then _b_50 := _b_50 + 1; end if;
        if _i_runs = 0 and _i_out then _b_ducks := _b_ducks + 1; end if;
      end if;
    end if;

    -- bowling
    select value into line from jsonb_array_elements(card->'bowling')
      where (value->>'member_id')::uuid = any(_members) limit 1;
    if line is not null then
      _i_legal := (line->>'legal_balls')::int; _i_conc := (line->>'runs_conceded')::int;
      _i_wkts := (line->>'wickets')::int; _i_maid := (line->>'maidens')::int;
      _i_wd := (line->>'wides')::int; _i_nb := (line->>'no_balls')::int;
      if _i_legal > 0 or _i_wd > 0 or _i_nb > 0 then    -- a bowling innings: delivered >=1 ball
        _w_inns := _w_inns + 1;
        _w_balls := _w_balls + _i_legal; _w_runs := _w_runs + _i_conc;
        _w_wkts := _w_wkts + _i_wkts; _w_maidens := _w_maidens + _i_maid;
        if (_i_wkts > _w_bbi_w) or (_i_wkts = _w_bbi_w and _i_conc < _w_bbi_r) then
          _w_bbi_w := _i_wkts; _w_bbi_r := _i_conc;     -- BBI: most wickets, then fewest runs
        end if;
        if _i_wkts = 4 then _w_4w := _w_4w + 1; end if;
        if _i_wkts >= 5 then _w_5w := _w_5w + 1; end if;
      end if;
    end if;

    -- fielding (a player can field across both innings of a match; accumulate every innings)
    select value into line from jsonb_array_elements(card->'fielding')
      where (value->>'member_id')::uuid = any(_members) limit 1;
    if line is not null then
      _f_ct := _f_ct + (line->>'catches')::int;
      _f_ro := _f_ro + (line->>'run_outs')::int;
      _f_st := _f_st + (line->>'stumpings')::int;
    end if;
  end loop;

  _bat_avg   := case when _b_outs > 0 then round(_b_runs::numeric / _b_outs, 2) else null end;
  _bat_sr    := case when _b_balls > 0 then round(100 * _b_runs::numeric / _b_balls, 2) else null end;
  _bowl_avg  := case when _w_wkts > 0 then round(_w_runs::numeric / _w_wkts, 2) else null end;
  _bowl_econ := case when _w_balls > 0 then round(_w_runs::numeric / (_w_balls::numeric / 6), 2) else null end;
  _bowl_sr   := case when _w_wkts > 0 then round(_w_balls::numeric / _w_wkts, 2) else null end;

  return jsonb_build_object(
    'player_key', _player_key,
    'matches', _mat,
    'batting', jsonb_build_object(
      'innings', _b_inns, 'not_outs', _b_inns - _b_outs, 'runs', _b_runs, 'balls', _b_balls,
      'highest', case when _b_inns = 0 then null else to_jsonb(_b_hs) end,
      'highest_not_out', _b_hs_notout,
      'average', _bat_avg, 'strike_rate', _bat_sr,
      'fours', _b_fours, 'sixes', _b_sixes, 'fifties', _b_50, 'hundreds', _b_100, 'ducks', _b_ducks),
    'bowling', jsonb_build_object(
      'innings', _w_inns, 'balls', _w_balls, 'runs', _w_runs, 'wickets', _w_wkts, 'maidens', _w_maidens,
      'overs', (_w_balls / 6)::text || '.' || (_w_balls % 6)::text,
      'best_wickets', case when _w_bbi_w < 0 then null else to_jsonb(_w_bbi_w) end,
      'best_runs', case when _w_bbi_w < 0 then null else to_jsonb(_w_bbi_r) end,
      'average', _bowl_avg, 'economy', _bowl_econ, 'strike_rate', _bowl_sr,
      'four_wickets', _w_4w, 'five_wickets', _w_5w),
    'fielding', jsonb_build_object('catches', _f_ct, 'run_outs', _f_ro, 'stumpings', _f_st)
  );
end; $$;
revoke all on function public.player_career_stats(uuid) from public;
grant execute on function public.player_career_stats(uuid) to anon, authenticated;
