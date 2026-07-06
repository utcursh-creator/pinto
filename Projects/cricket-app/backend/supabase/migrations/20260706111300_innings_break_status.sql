-- SCOR-1 residue: matches.status now actually passes through 'innings_break'.
-- The console calls mark_innings_break when the first innings closes (the
-- matches broadcast trigger pushes the change to viewers), and start_innings
-- flips it back to 'live' for the chase.
create or replace function public.mark_innings_break(_match_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_match_scorer(_match_id) then raise exception 'not authorized' using errcode = 'P0001'; end if;
  update public.matches set status = 'innings_break'
   where id = _match_id and status = 'live';
end; $$;
revoke all on function public.mark_innings_break(uuid) from public;
grant execute on function public.mark_innings_break(uuid) to authenticated;
