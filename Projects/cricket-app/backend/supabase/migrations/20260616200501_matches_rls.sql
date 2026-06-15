grant select, insert, update, delete on public.matches to authenticated;

create policy "matches_select_authenticated" on public.matches
  for select to authenticated using (true);

create policy "matches_insert_own" on public.matches
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy "matches_update_scorer" on public.matches
  for update to authenticated
  using (public.is_match_scorer(id)) with check (public.is_match_scorer(id));

create policy "matches_delete_owner" on public.matches
  for delete to authenticated using (owner_id = (select auth.uid()));
