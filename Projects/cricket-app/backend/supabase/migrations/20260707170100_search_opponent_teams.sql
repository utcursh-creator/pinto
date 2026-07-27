-- Found while reading the match-setup path (fix run 2026-07-07): the Opponent
-- picker on Start-a-match was fed by
--   from('teams').select('id, name, city').order('name')
-- with no limit and no filter. That is the entire teams table, downloaded to the
-- phone every time anyone opens the screen, and then poured into a
-- DropdownButton. At the size this app is meant to reach it is both a download
-- no phone should make and a list in which nobody can find their opponent.
--
-- What a scorer actually does is play the same few clubs over and over, and type
-- a name when it is someone new. So the server answers that question directly:
--   * no query  -> the clubs THIS user has recently played (their teams' past
--                  opponents), most recent first
--   * a query   -> a bounded name search across all teams
-- Either way the answer is capped, so the screen's cost no longer grows with the
-- size of the database.

create or replace function public.search_opponent_teams(
  _query text default null,
  _exclude uuid default null
) returns table (
  id uuid, name text, city text, logo_url text, last_played timestamptz
) language sql security definer set search_path = public stable as $$
  with me as (select auth.uid() as uid),
  -- the teams the caller belongs to; their matches are the caller's history
  mine as (
    select tm.team_id from public.team_members tm, me
     where tm.profile_id = me.uid
  ),
  played as (
    select case when m.team_a_id in (select team_id from mine)
                then m.team_b_id else m.team_a_id end as team_id,
           max(m.created_at) as last_played
      from public.matches m
     where m.team_a_id in (select team_id from mine)
        or m.team_b_id in (select team_id from mine)
     group by 1
  )
  select t.id, t.name, t.city, t.logo_url, p.last_played
    from public.teams t
    left join played p on p.team_id = t.id
   where (select uid from me) is not null
     and (_exclude is null or t.id <> _exclude)
     and case
           -- fewer than two characters is not a search, it is an empty box:
           -- answer with history rather than an arbitrary alphabetical slice
           when length(coalesce(trim(_query), '')) < 2 then p.last_played is not null
           else t.name ilike '%' || trim(_query) || '%'
         end
   order by p.last_played desc nulls last, t.name
   limit 25;
$$;
revoke all on function public.search_opponent_teams(text, uuid) from public;
grant execute on function public.search_opponent_teams(text, uuid) to authenticated;
