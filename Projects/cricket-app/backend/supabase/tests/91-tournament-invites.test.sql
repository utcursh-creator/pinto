begin;
select plan(11);
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
  format($$ select public.create_tournament_invite(%L) $$, :'_t'),
  'P0001', 'not authorized', 'a non-organizer cannot mint a tournament invite');

-- organizer mints the token (a)
select tests.authenticate_as('org@s.dev');
select public.create_tournament_invite(:'_t'::uuid) as _tok \gset
select ok(length(:'_tok'::text) >= 40, 'the organizer mints a long unguessable join token');

-- captain owns a team (they created it -> admin) that the organizer does NOT admin
select tests.authenticate_as('capt@s.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('capt@s.dev'), 'Capt');
select public.create_team('Strikers', 'C') as _team \gset

-- the captain redeems the token, entering THEIR team. The RPC returns the
-- tournament id so the joiner can be routed to it.
--
-- The redeemer no longer chooses the group: entry and PLACEMENT are separate
-- (penetration review 2026-07-07). Placement is the organizer's call via
-- set_tournament_team_group, because an invited club cannot be allowed to pick
-- its own group. Entry always lands in 'A' and the organizer moves it.
select is(public.join_tournament_with_token(:'_tok'::text, :'_team'::uuid),
  :'_t'::uuid, 'redeeming returns the joined tournament id');
select is(
  (select group_label from public.tournament_teams
     where tournament_id = :'_t'::uuid and team_id = :'_team'::uuid),
  'A', 'entry lands the team in group A; the organizer places it');
select is(
  (select added_via from public.tournament_teams
     where tournament_id = :'_t'::uuid and team_id = :'_team'::uuid),
  'invite', 'the team is tagged as invite-joined');

-- only the organizer can read the invite rows (RLS), so check the status as them (g)
select tests.authenticate_as('org@s.dev');
-- MULTI-USE (2026-07-07): status is no longer flipped on redemption; `uses` is
-- incremented instead, so the link keeps working for the rest of the group.
select is(
  (select status::text from public.tournament_invites where invite_token = :'_tok'),
  'pending', 'the invite stays live: it is multi-use now, so one share reaches a whole group');

-- (h) the invite-joined team flows into the tournament: it shows in standings at P0
select is(
  (select (e->>'points')::int
     from jsonb_array_elements(public.tournament_standings(:'_t'::uuid)->'groups') g,
          jsonb_array_elements(g->'rows') e
     where e->>'team_id' = :'_team'),
  0, 'the invite-joined team appears in standings at P0');

-- The token is MULTI-USE now (2026-07-07): an organizer shares one link with a
-- whole group of clubs, so a second redemption must WORK, and re-redeeming for a
-- team already entered must burn no additional use.
select tests.authenticate_as('capt@s.dev');
select lives_ok(
  format($$ select public.join_tournament_with_token(%L, %L) $$, :'_tok'::text, :'_team'::uuid),
  'the link still works after one redemption (multi-use)');
-- tournament_invites is organizer-only readable, so read the row AS the
-- organizer (a lesson this suite has learned before).
select tests.authenticate_as('org@s.dev');
select is((select uses from public.tournament_invites where invite_token = :'_tok'),
  1, 're-redeeming for an already-entered team burns no extra use');
select tests.authenticate_as('capt@s.dev');

-- a user who is NOT admin of the chosen team cannot redeem (c) - the consent gate
select tests.authenticate_as('org@s.dev');
select public.create_tournament_invite(:'_t'::uuid) as _tok2 \gset
select tests.authenticate_as('rando@s.dev');
select throws_ok(
  format($$ select public.join_tournament_with_token(%L, %L) $$, :'_tok2'::text, :'_team'::uuid),
  'P0001', 'you must be an admin of the team you are entering',
  'a non-admin of the team cannot enter it with a valid token');

-- redemption after registration closes (tournament left setup) fails (d).
-- the organizer moves the tournament out of setup (RLS: only they may).
select tests.authenticate_as('org@s.dev');
-- FIXTURE: moving the tournament out of setup is a state change the RPCs own
-- (generate_group_fixtures does it); clients no longer hold UPDATE on
-- tournaments, so seed the state as the owner.
select current_role as _seedrole91 \gset
set local role postgres;
update public.tournaments set status = 'group_stage' where id = :'_t'::uuid;
set local role :_seedrole91;
select tests.authenticate_as('capt@s.dev');
select public.create_team('Late', 'C') as _late \gset
select throws_ok(
  format($$ select public.join_tournament_with_token(%L, %L) $$, :'_tok2'::text, :'_late'::uuid),
  'P0001', 'registration is closed for this tournament',
  'a token cannot be redeemed once the tournament leaves setup');

select * from finish();
rollback;
