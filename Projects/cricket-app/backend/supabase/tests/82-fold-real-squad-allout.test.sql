begin;
select plan(3);
-- SCOR-10: all-out must trigger at the REAL squad size, not a hardcoded 11.
-- A 2-player batting squad is all out after a single wicket.
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('cap@s.dev'), 'Cap');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'S')  as _s  \gset
select public.add_guest_member(:'_a'::uuid, 'NS') as _ns \gset
select public.add_guest_member(:'_b'::uuid, 'Bowl') as _bw \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _mt \gset

-- a real 2-player batting squad (no rules.squad_size override)
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_s'::uuid,  1, false, false);
select public.add_squad_member(:'_mt'::uuid, :'_a'::uuid, :'_ns'::uuid, 2, false, false);
select public.start_innings(:'_mt'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_s'::uuid, :'_ns'::uuid) as _in \gset

-- one wicket (striker bowled); with only 2 in the squad this is all out
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id, seq, bowler_id, striker_id, non_striker_id, wicket_type, dismissed_player_id)
values (:'_in'::uuid, 1, :'_bw'::uuid, :'_s'::uuid, :'_ns'::uuid, 'bowled', :'_s'::uuid);
set local role :_seedrole;

select is((public.compute_innings_state(:'_in'::uuid)->>'wickets')::int, 1, 'one wicket recorded');
select is(public.compute_innings_state(:'_in'::uuid)->>'innings_status', 'completed',
  'a 2-player squad is all out at 1 wicket (squad_size from real match_squad, not 11)');
select is((public.compute_innings_state(:'_in'::uuid)->>'wickets_remaining')::int, 0, 'no wickets remaining');

select * from finish();
rollback;
