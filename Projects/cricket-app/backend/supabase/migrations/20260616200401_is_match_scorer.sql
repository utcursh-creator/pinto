create or replace function public.is_match_scorer(_match_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.matches
    where id = _match_id and scorer_id = (select auth.uid())
  );
$$;

revoke all on function public.is_match_scorer(uuid) from public;
grant execute on function public.is_match_scorer(uuid) to authenticated;
