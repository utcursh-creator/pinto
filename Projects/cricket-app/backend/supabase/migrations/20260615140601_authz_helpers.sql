-- SECURITY DEFINER + SET search_path => non-inlinable, so reading team_members inside
-- these helpers does NOT re-trigger team_members RLS (prevents policy recursion).
create or replace function public.is_team_member(_team_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.team_members
    where team_id = _team_id and profile_id = auth.uid()
  );
$$;

create or replace function public.is_team_admin(_team_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.team_members
    where team_id = _team_id
      and profile_id = auth.uid()
      and role in ('captain', 'admin')
  );
$$;

revoke all on function public.is_team_member(uuid) from public;
revoke all on function public.is_team_admin(uuid)  from public;
grant execute on function public.is_team_member(uuid) to authenticated;
grant execute on function public.is_team_admin(uuid)  to authenticated;
