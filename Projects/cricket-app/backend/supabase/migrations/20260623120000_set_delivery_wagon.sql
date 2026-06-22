-- Attach a wagon-wheel shot location to an existing delivery. The scorer
-- records the ball via record_ball (which returns the wagon_applicable hint),
-- then taps the shot; this persists just the wagon columns. Scorer-gated.
create or replace function public.set_delivery_wagon(
  _delivery_id uuid, _wagon_x real, _wagon_y real, _wagon_zone smallint
) returns void language plpgsql security definer set search_path = public as $$
declare _match_id uuid;
begin
  select i.match_id into _match_id
  from public.deliveries d join public.innings i on i.id = d.innings_id
  where d.id = _delivery_id;
  if _match_id is null then
    raise exception 'delivery not found' using errcode = 'P0001';
  end if;
  if not public.is_match_scorer(_match_id) then
    raise exception 'not authorized' using errcode = 'P0001';
  end if;
  update public.deliveries
     set wagon_x = _wagon_x, wagon_y = _wagon_y, wagon_zone = _wagon_zone,
         updated_at = now()
   where id = _delivery_id;
end; $$;

revoke all on function public.set_delivery_wagon(uuid, real, real, smallint) from public;
grant execute on function public.set_delivery_wagon(uuid, real, real, smallint) to authenticated;
