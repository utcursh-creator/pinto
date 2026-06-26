create or replace function public.create_tournament(
  _name text, _overs int, _group_count int, _qualifiers_per_group int,
  _balls_per_over int default 6, _ball_type public.ball_type default null,
  _city text default null, _venue text default null,
  _starts_on date default null, _ends_on date default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare _id uuid; _uid uuid := (select auth.uid());
begin
  if _uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  insert into public.tournaments(name, organizer_id, overs_limit, balls_per_over, ball_type,
                                 group_count, qualifiers_per_group, city, venue, starts_on, ends_on)
  values (_name, _uid, _overs, _balls_per_over, _ball_type,
          _group_count, _qualifiers_per_group, _city, _venue, _starts_on, _ends_on)
  returning id into _id;
  return _id;
end; $$;
revoke all on function public.create_tournament(text,int,int,int,int,public.ball_type,text,text,date,date) from public;
grant execute on function public.create_tournament(text,int,int,int,int,public.ball_type,text,text,date,date) to authenticated;
