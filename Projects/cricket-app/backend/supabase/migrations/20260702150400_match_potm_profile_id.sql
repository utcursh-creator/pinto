-- TOUR-7/8: expose profile_id (and keep team_id) on the POTM so the UI can link
-- a claimed player to /player/:profileId and show their team. Recomputed on view
-- as before (persisting at result time is a later refinement).
create or replace function public.match_potm(_match_id uuid)
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
revoke all on function public.match_potm(uuid) from public;
grant execute on function public.match_potm(uuid) to anon, authenticated;
