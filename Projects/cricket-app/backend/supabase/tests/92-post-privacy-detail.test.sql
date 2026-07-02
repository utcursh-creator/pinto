begin;
select plan(6);
-- SEC-2: the raw looking_for_posts row (with exact geog) is no longer readable
-- by anyone but the author; the feed + detail go through the SECURITY DEFINER
-- RPCs, which return only a coarsened distance + place_label and now the author
-- + team names (DISC-5).
select tests.create_supabase_user('auth@m.dev');
select tests.create_supabase_user('viewer@m.dev');

select tests.authenticate_as('auth@m.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('auth@m.dev'), 'Author');
select public.create_team('Strikers', 'C') as _tm \gset
select public.create_looking_for_post(
  'team_seeking_players', 'practice_match', 19.07, 72.87, 'need 2',
  :'_tm'::uuid, 'Sunday game', null, 20, null, 2) as _p \gset

-- the author can still read their own post row (self policy)
select is((select count(*)::int from public.looking_for_posts where id = :'_p'::uuid),
  1, 'the author can read their own post');

-- another authenticated user CANNOT read the raw row (no geog trilateration)
select tests.authenticate_as('viewer@m.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('viewer@m.dev'), 'Viewer');
select is((select count(*)::int from public.looking_for_posts where id = :'_p'::uuid),
  0, 'another user cannot read the raw post row (geog hidden)');

-- the feed RPC still returns it, with author + team names (DISC-5)
select is((select author_name from public.discover_posts(19.07, 72.87, 25000) where post_id = :'_p'::uuid),
  'Author', 'discover_posts returns the author name');
select is((select team_name from public.discover_posts(19.07, 72.87, 25000) where post_id = :'_p'::uuid),
  'Strikers', 'discover_posts returns the team name');

-- post_detail returns the names and NEVER a geog key
select is(public.post_detail(:'_p'::uuid)->>'author_name', 'Author',
  'post_detail returns the author name');
select ok(not (public.post_detail(:'_p'::uuid) ? 'geog'),
  'post_detail never exposes geog');

select * from finish();
rollback;
