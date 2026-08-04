-- player_public_profile composes identity + career + recent_form in one call,
-- anon-resolvable for a player with a completed match.
begin;
select plan(4);
select tests.create_supabase_user('cap@s.dev');
select tests.authenticate_as('cap@s.dev');
insert into public.profiles(id,display_name,batting_style) values (tests.get_supabase_uid('cap@s.dev'),'Cap','right');
select tests.get_supabase_uid('cap@s.dev') as _uid \gset
select public.create_team('A','P') as _a \gset
select public.create_team('B','P') as _b \gset
select id as _cap from public.team_members where profile_id = :'_uid'::uuid and team_id = :'_a'::uuid \gset
select public.add_guest_member(:'_a'::uuid,'P2') as _p2 \gset
select public.add_guest_member(:'_b'::uuid,'Bw') as _bw \gset
select public.create_match(:'_a'::uuid,:'_b'::uuid,20,12) as _m \gset
select public.add_squad_member(:'_m'::uuid,:'_a'::uuid,:'_cap'::uuid);
select public.start_innings(:'_m'::uuid,1,:'_a'::uuid,:'_b'::uuid,:'_cap'::uuid,:'_p2'::uuid) as _in \gset
select current_role as _seedrole \gset
set local role postgres;
insert into public.deliveries(innings_id,seq,bowler_id,striker_id,non_striker_id,runs_off_bat)
  select :'_in'::uuid, g, :'_bw'::uuid, :'_cap'::uuid, :'_p2'::uuid, 6 from generate_series(1,3) g;
set local role :_seedrole;
select public.set_match_result(:'_m'::uuid,'win_by_runs'::public.result_type,:'_a'::uuid);

select tests.clear_authentication();
select is(public.player_public_profile(:'_uid'::uuid)->'profile'->>'display_name', 'Cap',
  'wrapper exposes anon-safe identity');
select is(public.player_public_profile(:'_uid'::uuid)->'profile'->>'batting_style', 'right',
  'wrapper exposes batting_style');
select is((public.player_public_profile(:'_uid'::uuid)->'career'->'batting'->>'runs')::int, 18,
  'wrapper embeds career batting (18 runs)');
select is(jsonb_array_length(public.player_public_profile(:'_uid'::uuid)->'recent_form'), 1,
  'wrapper embeds the recent-form array');

select * from finish();
rollback;
