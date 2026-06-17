-- Sub-project 4, Task 6: login-free viewing. Anon SELECT on the viewer tables,
-- gated by match status so pre-match setup stays private. RLS is row-level, so we
-- rely on these tables having no sensitive columns (phone/email live on profiles,
-- which is never opened to anon; team_members holds only guest_name + orientation).
grant select on public.matches, public.innings, public.deliveries, public.match_squad, public.team_members, public.teams to anon;

create policy "matches_select_anon" on public.matches
  for select to anon
  using (status in ('live','innings_break','complete','abandoned'));

create policy "innings_select_anon" on public.innings
  for select to anon
  using (exists (
    select 1 from public.matches m
    where m.id = innings.match_id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy "deliveries_select_anon" on public.deliveries
  for select to anon
  using (exists (
    select 1 from public.innings i
    join public.matches m on m.id = i.match_id
    where i.id = deliveries.innings_id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy "match_squad_select_anon" on public.match_squad
  for select to anon
  using (exists (
    select 1 from public.matches m
    where m.id = match_squad.match_id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy "team_members_select_anon" on public.team_members
  for select to anon
  using (exists (
    select 1 from public.match_squad ms
    join public.matches m on m.id = ms.match_id
    where ms.team_member_id = team_members.id
      and m.status in ('live','innings_break','complete','abandoned')));

create policy "teams_select_anon" on public.teams
  for select to anon
  using (exists (
    select 1 from public.matches m
    where (m.team_a_id = teams.id or m.team_b_id = teams.id)
      and m.status in ('live','innings_break','complete','abandoned')));
