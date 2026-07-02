begin;
select plan(7);
-- Slice 3 (RT-2, SEC-9, SEC-10): the innings + matches broadcast triggers exist,
-- and the receive gate only authorizes topics for a publicly-viewable match.

-- the two new AFTER triggers push innings-start + match-completion (RT-2)
select has_trigger('public', 'innings', 'innings_broadcast',
  'an AFTER trigger on innings broadcasts new/updated innings');
select has_trigger('public', 'matches', 'matches_broadcast',
  'an AFTER trigger on matches broadcasts status/result changes');
select has_function('public', 'match_is_publicly_viewable', array['uuid'],
  'the receive-gate helper exists');

select tests.create_supabase_user('sc@s.dev');
select tests.authenticate_as('sc@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('sc@s.dev'), 'Sc');
select public.create_team('A', 'P') as _a \gset
select public.create_team('B', 'P') as _b \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset

-- a match still in setup is NOT publicly viewable (SEC-9)
select is(public.match_is_publicly_viewable(:'_m'::uuid), false,
  'a setup match is not publicly viewable');

-- once live, it is viewable (the matches_broadcast trigger also fires harmlessly)
update public.matches set status = 'live' where id = :'_m'::uuid;
select is(public.match_is_publicly_viewable(:'_m'::uuid), true,
  'a live match is publicly viewable');

-- a completed match stays viewable (history)
update public.matches set status = 'complete' where id = :'_m'::uuid;
select is(public.match_is_publicly_viewable(:'_m'::uuid), true,
  'a completed match is publicly viewable');

-- a random non-existent id is not viewable
select is(public.match_is_publicly_viewable(gen_random_uuid()), false,
  'an unknown match id is not viewable');

select * from finish();
rollback;
