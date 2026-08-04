-- player_recent_form: newest-first, limited to _n, one collapsed batting+bowling
-- line per match (summed across innings). Three completed matches with distinct
-- created_at; the newest is a two-innings match where cap batted AND bowled.
begin;
select plan(6);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = tests.get_supabase_uid('cap@s.dev') and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_b'::uuid,'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid,'b2') as _b2 \gset
select public.add_guest_member(:'_b'::uuid,'b3') as _b3 \gset

-- helper: a one-innings match where cap scores `_runs6*6` via sixes
-- OLD match: cap 10 (a four + a six)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _mo \gset
select public.add_squad_member(:'_mo'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_mo'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _io \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat) values
  (:'_io'::uuid,1,:'_b1'::uuid,:'_cap'::uuid,:'_p2'::uuid,4),(:'_io'::uuid,2,:'_b1'::uuid,:'_cap'::uuid,:'_p2'::uuid,6);
set local role :_seedrole;
select public.set_match_result(:'_mo'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
update public.matches set created_at = now() - interval '3 days' where id = :'_mo'::uuid;
select tests.authenticate_as('cap@s.dev');

-- MID match: cap 20 (a four + ... ) -> 20 via 5 fours
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _mm \gset
select public.add_squad_member(:'_mm'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_mm'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _im \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_im'::uuid, g, :'_b1'::uuid, :'_cap'::uuid, :'_p2'::uuid, 4 from generate_series(1,5) g;
set local role :_seedrole;
select public.set_match_result(:'_mm'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
update public.matches set created_at = now() - interval '2 days' where id = :'_mm'::uuid;
select tests.authenticate_as('cap@s.dev');

-- NEW match (two innings): cap bats 30 (inns1) and bowls 2 wickets (inns2)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _mn \gset
select public.add_squad_member(:'_mn'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_mn'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _in1 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_in1'::uuid, g, :'_b1'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,5) g;
set local role :_seedrole;
select public.start_innings(:'_mn'::uuid,2,:'_b'::uuid,:'_a'::uuid,:'_b1'::uuid,:'_b2'::uuid) as _in2 \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,wicket_type,incoming_batter_id) values
  (:'_in2'::uuid,1,:'_cap'::uuid,:'_b1'::uuid,:'_b2'::uuid,'bowled',:'_b3'::uuid),
  (:'_in2'::uuid,2,:'_cap'::uuid,:'_b3'::uuid,:'_b2'::uuid,'bowled',:'_b1'::uuid);
set local role :_seedrole;
select public.set_match_result(:'_mn'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);
reset role;  -- fixture setup: this write is no longer granted to clients
update public.matches set created_at = now() - interval '1 day' where id = :'_mn'::uuid;
select tests.authenticate_as('cap@s.dev');

select is(jsonb_array_length(public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),2)), 2,
  'recent form respects the _n limit (2)');
select is((public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),2)->0->'bat'->>'runs')::int, 30,
  'newest match first: 30 runs');
select is((public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),2)->0->'bowl'->>'wickets')::int, 2,
  'newest match collapses both innings: 2 wickets bowled');
select is((public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),2)->1->'bat'->>'runs')::int, 20,
  'second-newest: 20 runs');
select is((public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),2)->1->'bowl'->>'wickets')::int, 0,
  'middle match: cap did not bowl');
select is(jsonb_array_length(public.player_recent_form(tests.get_supabase_uid('cap@s.dev'),5)), 3,
  '_n larger than history returns all 3 completed matches');

select * from finish();
rollback;
