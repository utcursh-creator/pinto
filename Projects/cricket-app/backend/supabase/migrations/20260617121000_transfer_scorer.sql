-- Sub-project 4, Task 4: mid-match scorer reassignment.
create or replace function public.transfer_scorer(_match_id uuid, _new_scorer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  _uid uuid := (select auth.uid());
  _m public.matches%rowtype;
  _is_caller_admin boolean;
  _is_new_eligible boolean;
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;

  -- serialise against a concurrent record_ball on the same match
  perform pg_advisory_xact_lock(hashtextextended(_match_id::text, 0));

  select * into _m from public.matches where id = _match_id for update;
  if not found then raise exception 'match not found' using errcode = 'P0001'; end if;

  -- status guard
  if _m.status not in ('setup','live','innings_break') then
    raise exception 'match status % does not allow a scorer transfer', _m.status using errcode = 'P0001';
  end if;

  -- authorization: current scorer, or an admin of either participating team
  _is_caller_admin := public.is_team_admin(_m.team_a_id) or public.is_team_admin(_m.team_b_id);
  if _uid <> _m.scorer_id and not _is_caller_admin then
    raise exception 'not authorized to transfer the scorer role' using errcode = '42501';
  end if;

  -- eligibility ALWAYS checked, even on a same-scorer no-op
  _is_new_eligible := exists (
    select 1 from public.team_members tm
    where tm.profile_id = _new_scorer_id
      and tm.team_id in (_m.team_a_id, _m.team_b_id)
  );
  if not _is_new_eligible then
    raise exception 'the new scorer must be a member of either team' using errcode = 'P0001';
  end if;

  -- validated no-op, else transfer
  if _m.scorer_id = _new_scorer_id then return; end if;
  update public.matches set scorer_id = _new_scorer_id where id = _match_id;
end; $$;

revoke all on function public.transfer_scorer(uuid, uuid) from public;
grant execute on function public.transfer_scorer(uuid, uuid) to authenticated;
