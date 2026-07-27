begin;
select plan(4);
-- MTCH-2: only the owner can delete a match; the delete cascades to innings;
-- a non-owner is refused; a tournament match cannot be deleted this way.
select tests.create_supabase_user('own@s.dev');
select tests.create_supabase_user('other@s.dev');

select tests.authenticate_as('own@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('own@s.dev'), 'Own');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- a non-owner cannot delete it
select tests.authenticate_as('other@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('other@s.dev'), 'Other');
select throws_ok(
  format($$ select public.delete_match(%L) $$, :'_m'),
  'P0001', 'only the match owner can delete this match',
  'a non-owner cannot delete the match');

-- the owner deletes it; the row (and by cascade its children) is gone
select tests.authenticate_as('own@s.dev');
select public.delete_match(:'_m'::uuid);
select is((select count(*)::int from public.matches where id = :'_m'::uuid), 0,
  'the match is deleted');

-- a tournament match is protected
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _tm \gset
insert into public.tournaments(id, name, organizer_id, overs_limit, group_count, qualifiers_per_group)
  values (gen_random_uuid(), 'Cup', tests.get_supabase_uid('own@s.dev'), 20, 1, 2)
  returning id as _t \gset
reset role;  -- fixture setup: this write is no longer granted to clients
insert into public.tournament_matches(match_id, tournament_id, stage)
  values (:'_tm'::uuid, :'_t'::uuid, 'group');
select tests.authenticate_as('own@s.dev');
select throws_ok(
  format($$ select public.delete_match(%L) $$, :'_tm'),
  'P0001', 'a tournament match cannot be deleted here',
  'a tournament match is not deletable via delete_match');
select is((select count(*)::int from public.matches where id = :'_tm'::uuid), 1,
  'the tournament match still exists');

select * from finish();
rollback;
