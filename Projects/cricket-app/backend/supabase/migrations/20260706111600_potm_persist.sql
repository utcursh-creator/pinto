-- TOUR-8: the player of the match is decided WHEN THE RESULT IS SET and stored,
-- so a later correction or view-time recompute cannot quietly change it.
-- set_match_result persists the computed POTM on the match; match_potm returns
-- the persisted pick when present and only computes for matches finished before
-- this migration.
alter table public.matches add column potm jsonb;

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

  -- TOUR-8: freeze the POTM at result time (needs the result row above so the
  -- winner-side tiebreak reads the final winner)
  update public.matches set potm = public.compute_match_potm(_match_id) where id = _match_id;
end; $$;
revoke all on function public.set_match_result(uuid, public.result_type, uuid, text) from public;
grant execute on function public.set_match_result(uuid, public.result_type, uuid, text) to authenticated;

-- the raw computation moves to compute_match_potm; match_potm becomes
-- "persisted if present, else computed" so old finished matches keep working
create or replace function public.compute_match_potm(_match_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
with inns as (select id from public.innings where match_id = _match_id),
cards as (select public.compute_innings_cards(id) c from inns),
contrib as (
  select (e->>'member_id')::uuid mid, (e->>'runs')::int v from cards, jsonb_array_elements(c->'batting') e
  union all
  select (e->>'member_id')::uuid, (e->>'wickets')::int * 20 from cards, jsonb_array_elements(c->'bowling') e
  union all
  select (e->>'member_id')::uuid,
         ((e->>'catches')::int + (e->>'run_outs')::int + (e->>'stumpings')::int) * 10
  from cards, jsonb_array_elements(c->'fielding') e
),
impact as (select mid, sum(v) imp from contrib group by mid)
select jsonb_build_object('member_id', r.mid, 'profile_id', r.profile_id,
                         'name', r.name, 'impact', r.imp, 'team_id', r.team_id)
from (
  select i.mid, i.imp, tmem.team_id, tmem.profile_id,
         coalesce(tmem.guest_name, p.display_name, 'Player') name
  from impact i
  join public.team_members tmem on tmem.id = i.mid
  left join public.profiles p on p.id = tmem.profile_id
  order by (tmem.team_id = (select (result->>'winner_team_id')::uuid from public.matches where id = _match_id)) desc nulls last,
           i.imp desc
  limit 1
) r;
$$;
revoke all on function public.compute_match_potm(uuid) from public;
grant execute on function public.compute_match_potm(uuid) to anon, authenticated;

create or replace function public.match_potm(_match_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  select coalesce(m.potm, public.compute_match_potm(_match_id))
  from public.matches m where m.id = _match_id;
$$;
revoke all on function public.match_potm(uuid) from public;
grant execute on function public.match_potm(uuid) to anon, authenticated;
