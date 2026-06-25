-- Login-free stats: anon resolves career + recent-form aggregates for completed
-- matches, but in-progress (live) data never leaks, and the identity views are
-- NOT broadly anon-selectable (anon reaches stats only through the definer RPCs).
begin;
select plan(5);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@s.dev'),'Cap');
select tests.get_supabase_uid('cap@s.dev') as _uid \gset
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = :'_uid'::uuid and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_b'::uuid,'Bw') as _bw \gset

-- COMPLETE match: cap 24 (4 sixes)
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,50) as _mc \gset
select public.add_squad_member(:'_mc'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_mc'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _ic \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_ic'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,4) g;
select public.set_match_result(:'_mc'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

-- LIVE match (no result): cap 36 - must NOT be visible to anon
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,50) as _ml \gset
select public.add_squad_member(:'_ml'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_ml'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _il \gset
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_il'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,6) g;

-- become anon
select tests.clear_authentication();
select is((public.player_career_stats(:'_uid'::uuid)->'batting'->>'runs')::int, 24,
  'anon resolves completed-match career runs (24)');
select is((public.player_career_stats(:'_uid'::uuid)->>'matches')::int, 1,
  'anon sees only the completed match (live excluded)');
select is(jsonb_array_length(public.player_recent_form(:'_uid'::uuid,5)), 1,
  'anon recent form returns the one completed match');
select throws_ok($$ select * from public.v_player_key $$, '42501', null,
  'anon cannot broadly select v_player_key');
select throws_ok($$ select * from public.v_player_matches $$, '42501', null,
  'anon cannot broadly select v_player_matches');

select * from finish();
rollback;
