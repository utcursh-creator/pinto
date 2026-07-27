begin;
select plan(8);
-- CRITICAL regression test (penetration review 2026-07-07, completeness critic):
-- a tournament assembled via invite links could never be split into groups,
-- because the organizer's group chips went through add_tournament_team, whose
-- SEC-8 is_team_admin gate the organizer cannot satisfy for someone else's club.

select tests.create_supabase_user('org@g.dev');
select tests.create_supabase_user('club@g.dev');

select tests.authenticate_as('org@g.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('org@g.dev'), 'Org');
select public.create_tournament('Sunday Cup', 4, 2, 8) as _t \gset

-- a club captain redeems the organizer's invite and enters their OWN team
select public.create_tournament_invite(:'_t'::uuid) as _tok \gset
select tests.authenticate_as('club@g.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('club@g.dev'), 'Club');
select public.create_team('Club XI', 'Pune') as _ct \gset
select isnt(public.join_tournament_with_token(:'_tok'::text, :'_ct'::uuid), null,
  'the club redeems the invite and is entered');
select is((select group_label from public.tournament_teams
            where tournament_id = :'_t'::uuid and team_id = :'_ct'::uuid), 'A',
  'the invite lands the team in group A (the default)');

-- THE BUG: the organizer tries to move that team to group B the old way
select tests.authenticate_as('org@g.dev');
select throws_ok(
  format($$ select public.add_tournament_team(%L, %L, 'B') $$, :'_t', :'_ct'),
  'P0001', 'you must be an admin of this team to enter it',
  'add_tournament_team still (correctly) refuses to ENTER someone else''s team');

-- THE FIX: placement is a separate, organizer-owned operation
select lives_ok(
  format($$ select public.set_tournament_team_group(%L, %L, 'B') $$, :'_t', :'_ct'),
  'the organizer CAN place an already-entered team into another group');
select is((select group_label from public.tournament_teams
            where tournament_id = :'_t'::uuid and team_id = :'_ct'::uuid), 'B',
  'the team moved to group B');

-- placement can never be used to enrol a team that never consented
select public.create_team('Never Entered', 'Pune') as _nt \gset
select throws_ok(
  format($$ select public.set_tournament_team_group(%L, %L, 'A') $$, :'_t', :'_nt'),
  'P0001', 'that team is not in this tournament',
  'placement cannot enrol a team (consent model preserved)');

-- only the organizer may place
select tests.authenticate_as('club@g.dev');
select throws_ok(
  format($$ select public.set_tournament_team_group(%L, %L, 'C') $$, :'_t', :'_ct'),
  'P0001', 'not authorized',
  'a club admin cannot re-place their own team');

-- garbage labels are rejected
select tests.authenticate_as('org@g.dev');
select throws_ok(
  format($$ select public.set_tournament_team_group(%L, %L, 'Group One') $$, :'_t', :'_ct'),
  'P0001', 'a group label must be a single letter',
  'a malformed group label is rejected');

select * from finish();
rollback;
