begin;
select plan(10);
-- SEC-8 proper fix: a team the organizer does NOT admin enters a tournament only
-- by that team's own admin redeeming a join token (consent-by-opt-in), mirroring
-- CricHeroes' invite-link / PIN model. Direct-add stays admin-gated.
select tests.create_supabase_user('org@s.dev');
select tests.create_supabase_user('capt@s.dev');   -- admin of the guest team
select tests.create_supabase_user('rando@s.dev');  -- admins nothing here

-- organizer creates a tournament and mints a join token
select tests.authenticate_as('org@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('org@s.dev'), 'Org');
select public.create_tournament('Cup', 20, 1, 2) as _t \gset

-- a non-organizer cannot mint a token (f)
select tests.authenticate_as('rando@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('rando@s.dev'), 'Rando');
select throws_ok(
  $$ select public.create_tournament_invite((select id from public.tournaments limit 1)) $$,
  'P0001', 'not authorized', 'a non-organizer cannot mint a tournament invite');

-- organizer mints the token (a)
select tests.authenticate_as('org@s.dev');
select public.create_tournament_invite(:'_t'::uuid) as _tok \gset
select ok(length(:'_tok'::text) >= 40, 'the organizer mints a long unguessable join token');

-- captain owns a team (they created it -> admin) that the organizer does NOT admin
select tests.authenticate_as('capt@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('capt@s.dev'), 'Capt');
select public.create_team('Strikers', 'C') as _team \gset

-- the captain redeems the token, dropping THEIR team into group B (b)(g). The
-- RPC returns the tournament id so the joiner can be routed to it.
select is(public.join_tournament_with_token(:'_tok'::text, :'_team'::uuid, 'B'),
  :'_t'::uuid, 'redeeming returns the joined tournament id');
select is(
  (select group_label from public.tournament_teams
     where tournament_id = :'_t'::uuid and team_id = :'_team'::uuid),
  'B', 'the redeemed team lands in the tournament in the chosen group');
select is(
  (select added_via from public.tournament_teams
     where tournament_id = :'_t'::uuid and team_id = :'_team'::uuid),
  'invite', 'the team is tagged as invite-joined');

-- only the organizer can read the invite rows (RLS), so check the status as them (g)
select tests.authenticate_as('org@s.dev');
select is(
  (select status::text from public.tournament_invites where invite_token = :'_tok'),
  'accepted', 'the invite is marked accepted after redemption');

-- (h) the invite-joined team flows into the tournament: it shows in standings at P0
select is(
  (select (e->>'points')::int
     from jsonb_array_elements(public.tournament_standings(:'_t'::uuid)->'groups') g,
          jsonb_array_elements(g->'rows') e
     where e->>'team_id' = :'_team'),
  0, 'the invite-joined team appears in standings at P0');

-- the token is single-use: a second redemption fails (e). Back to the team admin
-- so we get past the consent check and hit the token check.
select tests.authenticate_as('capt@s.dev');
select throws_ok(
  format($$ select public.join_tournament_with_token(%L, %L, 'B') $$, :'_tok'::text, :'_team'::uuid),
  'P0001', 'invite not found or already used', 'a used token cannot be redeemed again');

-- a user who is NOT admin of the chosen team cannot redeem (c) - the consent gate
select tests.authenticate_as('org@s.dev');
select public.create_tournament_invite(:'_t'::uuid) as _tok2 \gset
select tests.authenticate_as('rando@s.dev');
select throws_ok(
  format($$ select public.join_tournament_with_token(%L, %L, 'A') $$, :'_tok2'::text, :'_team'::uuid),
  'P0001', 'you must be an admin of the team you are entering',
  'a non-admin of the team cannot enter it with a valid token');

-- redemption after registration closes (tournament left setup) fails (d).
-- the organizer moves the tournament out of setup (RLS: only they may).
select tests.authenticate_as('org@s.dev');
update public.tournaments set status = 'group_stage' where id = :'_t'::uuid;
select tests.authenticate_as('capt@s.dev');
select public.create_team('Late', 'C') as _late \gset
select throws_ok(
  format($$ select public.join_tournament_with_token(%L, %L, 'A') $$, :'_tok2'::text, :'_late'::uuid),
  'P0001', 'registration is closed for this tournament',
  'a token cannot be redeemed once the tournament leaves setup');

select * from finish();
rollback;
