-- Whole-system review #2 (2026-07-28), findings 10 and 25 (both HIGH): nothing
-- in the app can take a player OUT of a match squad.
--
-- The squads screen wrote the XI one row at a time with add_squad_member, which
-- is additive and idempotent, and un-ticking someone only changed a local Set.
-- So a player dropped on a resumed setup stayed in match_squad and kept turning
-- up in the opening-pair dropdowns, the console's batter/bowler/fielder pickers
-- and the public scorecard - and once a ball was credited to him,
-- player_career_stats baked a permanent public career record for a man who
-- never played. The same loop was not atomic: a failure on the 8th of 12 rows
-- left 7 committed under an error message that said nothing was saved.
--
-- This states the WHOLE squad in one transaction: what is not in the list is
-- not in the squad. The guards from add_squad_member are kept, and one is
-- added - a player who has already faced, bowled or been dismissed cannot be
-- removed, because that would orphan his deliveries and rewrite a real
-- scorecard.
--
-- _members is an array of {team_id, team_member_id, is_captain?, is_keeper?};
-- batting_order is the position within each team's list, so the caller cannot
-- produce two players sharing a slot.
create or replace function public.set_match_squad(_match_id uuid, _members jsonb)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _bad uuid;
begin
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  if jsonb_typeof(_members) <> 'array' then
    raise exception 'the squad must be a list' using errcode = 'P0001';
  end if;

  create temp table _wanted on commit drop as
  select (e->>'team_id')::uuid        as team_id,
         (e->>'team_member_id')::uuid as team_member_id,
         coalesce((e->>'is_captain')::boolean, false) as is_captain,
         coalesce((e->>'is_keeper')::boolean, false)  as is_keeper,
         row_number() over (partition by (e->>'team_id')::uuid
                            order by ord)::int        as batting_order
    from jsonb_array_elements(_members) with ordinality as t(e, ord);

  -- one row per player, whichever side they were listed under
  if exists (select 1 from _wanted group by team_member_id having count(*) > 1) then
    raise exception 'a player can only be listed once' using errcode = 'P0001';
  end if;

  -- the same two guards add_squad_member applies, per row
  if exists (select 1 from _wanted w
              where not exists (select 1 from public.matches m
                                 where m.id = _match_id
                                   and w.team_id in (m.team_a_id, m.team_b_id))) then
    raise exception 'that team is not in this match' using errcode = 'P0001';
  end if;
  if exists (select 1 from _wanted w
              where not exists (select 1 from public.team_members tm
                                 where tm.id = w.team_member_id
                                   and tm.team_id = w.team_id)) then
    raise exception 'that player is not in that team' using errcode = 'P0001';
  end if;

  -- NEW guard: a player with a ball to his name is part of the record
  select ms.team_member_id into _bad
    from public.match_squad ms
   where ms.match_id = _match_id
     and not exists (select 1 from _wanted w
                      where w.team_member_id = ms.team_member_id)
     and exists (
       select 1
         from public.deliveries d
         join public.innings i on i.id = d.innings_id
        where i.match_id = _match_id
          and ms.team_member_id in (d.striker_id, d.non_striker_id, d.bowler_id,
                                    d.dismissed_player_id, d.incoming_batter_id,
                                    d.fielder_id))
   limit 1;
  if _bad is not null then
    raise exception 'that player has already played in this match'
      using errcode = 'P0001';
  end if;

  delete from public.match_squad ms
   where ms.match_id = _match_id
     and not exists (select 1 from _wanted w
                      where w.team_member_id = ms.team_member_id);

  insert into public.match_squad(match_id, team_id, team_member_id,
                                 batting_order, is_captain, is_wicket_keeper)
  select _match_id, w.team_id, w.team_member_id, w.batting_order,
         w.is_captain, w.is_keeper
    from _wanted w
  on conflict (match_id, team_member_id) do update
    set team_id          = excluded.team_id,
        batting_order    = excluded.batting_order,
        is_captain       = excluded.is_captain,
        is_wicket_keeper = excluded.is_wicket_keeper;

  drop table _wanted;
end; $function$;

revoke all on function public.set_match_squad(uuid, jsonb) from public;
grant execute on function public.set_match_squad(uuid, jsonb) to authenticated;
