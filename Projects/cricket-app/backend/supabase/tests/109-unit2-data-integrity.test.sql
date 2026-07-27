begin;
select plan(9);
-- HIGH batch 2 (penetration review 2026-07-07): data destruction and dead ends.

select tests.create_supabase_user('di@d.dev');
select tests.authenticate_as('di@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('di@d.dev'), 'Di');
select public.create_team('DI A', 'P') as _a \gset
select public.create_team('DI B', 'P') as _b \gset
select public.add_guest_member(:'_a'::uuid, 'a1') as _a1 \gset
select public.add_guest_member(:'_a'::uuid, 'a2') as _a2 \gset
select public.add_guest_member(:'_a'::uuid, 'a3') as _a3 \gset
select public.add_guest_member(:'_b'::uuid, 'b1') as _b1 \gset
select public.add_guest_member(:'_b'::uuid, 'b2') as _b2 \gset
select public.create_match(:'_a'::uuid, :'_b'::uuid, 20) as _m \gset
select public.start_innings(:'_m'::uuid, 1, :'_a'::uuid, :'_b'::uuid, :'_a1'::uuid, :'_a2'::uuid) as _i \gset

-- 1. edit_ball is a FULL overwrite: the corrections UI cannot read or resend
--    extra_penalty / crossed / is_overthrow / the wagon shot, so editing any
--    ball silently destroys them. It must patch, not overwrite.
select public.record_ball(:'_i'::uuid, :'_b1'::uuid, 2, _extra_penalty := 5,
       _is_overthrow := true, _wagon_x := 0.4::real, _wagon_y := 0.6::real, _wagon_zone := 3::smallint);
select id as _d1 from public.deliveries where innings_id = :'_i'::uuid and seq = 1 \gset

-- a realistic UI edit: "this was 3 runs, not 2" - it sends only runs_off_bat
select public.edit_ball(:'_d1'::uuid, _runs_off_bat := 3);

select is((select extra_penalty from public.deliveries where id = :'_d1'::uuid), 5,
  'editing runs does NOT wipe the penalty runs');
select is((select is_overthrow from public.deliveries where id = :'_d1'::uuid), true,
  'editing runs does NOT wipe the overthrow flag');
select is((select wagon_zone from public.deliveries where id = :'_d1'::uuid), 3::smallint,
  'editing runs does NOT wipe the wagon-wheel shot');
select is((select runs_off_bat from public.deliveries where id = :'_d1'::uuid), 3,
  'the edit itself applied');

-- clearing a value must still be possible, explicitly
select public.edit_ball(:'_d1'::uuid, _runs_off_bat := 3, _clear_wagon := true);
select is((select wagon_zone from public.deliveries where id = :'_d1'::uuid), null,
  'an explicit clear still works');

-- 2. record_ball must refuse the retirement wicket types: those are non-ball
--    EVENTS (retire_batter). Through record_ball they consume a ball, charge the
--    bowler, and dismiss the striker rather than the named batter.
select throws_ok(
  format($$ select public.record_ball(%L, %L, 0, _wicket_type := 'retired_out',
              _dismissed_player_id := %L, _incoming_batter_id := %L) $$,
    :'_i', :'_b1', :'_a1', :'_a3'),
  'P0001', 'a retirement is not a ball - use retire_batter',
  'record_ball refuses retired_out');
select throws_ok(
  format($$ select public.record_ball(%L, %L, 0, _wicket_type := 'timed_out',
              _dismissed_player_id := %L, _incoming_batter_id := %L) $$,
    :'_i', :'_b1', :'_a1', :'_a3'),
  'P0001', 'a retirement is not a ball - use retire_batter',
  'record_ball refuses timed_out');

-- 3. delete_my_account must never abort. Today it FK-aborts for anyone who
--    created a team or appeared in a squad - i.e. essentially every real user -
--    which is also the Play Store rejection.
select tests.create_supabase_user('del@d.dev');
select tests.authenticate_as('del@d.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('del@d.dev'), 'Deleter');
select public.create_team('Deleter XI', 'P') as _dt \gset
select tests.get_supabase_uid('del@d.dev') as _duid \gset
select lives_ok('select public.delete_my_account()',
  'a user who created a team can delete their account');
select is((select display_name from public.profiles where id = :'_duid'::uuid),
  'Deleted user',
  'the profile is anonymized rather than left behind or FK-blocking');

select * from finish();
rollback;
