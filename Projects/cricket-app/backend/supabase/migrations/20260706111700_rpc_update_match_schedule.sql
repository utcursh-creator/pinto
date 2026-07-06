-- TOUR-4: generated fixtures finally get a date + ground. The match scorer or
-- the tournament organizer (for tournament fixtures) can set/clear
-- scheduled_at + venue until the match has a final result.
create or replace function public.update_match_schedule(
  _match_id uuid, _scheduled_at timestamptz default null, _venue text default null
) returns void language plpgsql security definer set search_path = public as $$
declare _st public.match_status;
begin
  if not (
    public.is_match_scorer(_match_id)
    or exists (
      select 1 from public.tournament_matches tm
      where tm.match_id = _match_id and public.is_tournament_organizer(tm.tournament_id))
  ) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;

  select status into _st from public.matches where id = _match_id;
  if _st is null then raise exception 'match not found' using errcode = 'P0001'; end if;
  if _st in ('complete','abandoned') then
    raise exception 'this match already finished' using errcode = 'P0001';
  end if;

  update public.matches
     set scheduled_at = _scheduled_at, venue = nullif(trim(_venue), '')
   where id = _match_id;
end; $$;
revoke all on function public.update_match_schedule(uuid, timestamptz, text) from public;
grant execute on function public.update_match_schedule(uuid, timestamptz, text) to authenticated;
