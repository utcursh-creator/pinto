begin;
select plan(4);
-- MISS-3: name search finds players + teams (case-insensitive substring),
-- requires >= 2 chars, and exposes only public-safe columns.
select tests.create_supabase_user('searcher@s.dev');
select tests.authenticate_as('searcher@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('searcher@s.dev'), 'Rohit Sharma');
select public.create_team('Mumbai Strikers', 'Mumbai') as _tm \gset

-- a player match (case-insensitive)
select is((select name from public.search_players_and_teams('rohit') where kind = 'player' limit 1),
  'Rohit Sharma', 'finds a player by a lowercase substring');
-- a team match, with its city as the subtitle
select is((select subtitle from public.search_players_and_teams('strikers') where kind = 'team' limit 1),
  'Mumbai', 'finds a team and returns its city as the subtitle');
-- a 1-char query is rejected by the min-length guard
select is((select count(*)::int from public.search_players_and_teams('a')),
  0, 'a 1-char query is rejected by the length guard');
-- a non-matching query is empty
select is((select count(*)::int from public.search_players_and_teams('zzzznomatch')),
  0, 'a non-matching query returns nothing');

select * from finish();
rollback;
