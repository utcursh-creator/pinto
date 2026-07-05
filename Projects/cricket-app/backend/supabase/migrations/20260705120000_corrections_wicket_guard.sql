-- SCOR-2/SCOR-5 (final-audit finding): the console's wicket-needs-incoming guard
-- existed only on record_ball - the ball-log corrections path (edit_ball /
-- insert_ball) could still write a mid-innings wicket with no incoming batter,
-- recreating the exact corruption the console fix closed (the fold keeps the
-- out batter at the crease). Guard: a wicket on a delivery that has (or will
-- have) LATER deliveries in the innings must name the incoming batter; a wicket
-- on the final recorded ball may omit it (the innings ends there), matching the
-- console's last-wicket case.
create or replace function public.correction_wicket_guard(
  _innings_id uuid, _seq int, _wicket_type public.wicket_type,
  _incoming uuid, _shifting boolean
) returns void language plpgsql as $$
begin
  if _wicket_type is null or _incoming is not null then return; end if;
  if _shifting or exists (
    select 1 from public.deliveries
    where innings_id = _innings_id and seq > _seq
  ) then
    raise exception 'a mid-innings wicket needs the incoming batter'
      using errcode = 'P0001';
  end if;
end; $$;
revoke all on function public.correction_wicket_guard(uuid,int,public.wicket_type,uuid,boolean) from public;
