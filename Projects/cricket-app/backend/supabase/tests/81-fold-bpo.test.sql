begin;
select plan(3);
-- SCOR-23: over notation + bowler overs must use matches.balls_per_over, not a
-- hardcoded 6. Score 5 legal balls in a 5-ball-over match: the over completes.
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@s.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid, 'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20, 5) as _mt \gset
select public.start_innings(:'_mt'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _in \gset

insert into public.deliveries(innings_id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat) values
 (:'_in'::uuid, 1, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 0),
 (:'_in'::uuid, 2, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 0),
 (:'_in'::uuid, 3, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 0),
 (:'_in'::uuid, 4, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 0),
 (:'_in'::uuid, 5, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 0);

select is((public.compute_innings_state(:'_in'::uuid)->>'legal_balls')::int, 5, '5 legal balls bowled');
select is(public.compute_innings_state(:'_in'::uuid)->>'over', '1.0',
  'a 5-ball over completes at 5 legal balls (over-math uses balls_per_over, not 6)');
select is(public.compute_innings_state(:'_in'::uuid)#>>'{bowling,0,overs}', '1.0',
  'bowler overs also use balls_per_over');

select * from finish();
rollback;
