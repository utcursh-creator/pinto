begin;
select plan(4);
-- LOW (fix-run re-review 2026-07-07): the notification fan-outs selected
-- recipients with `role in ('captain','admin')` and never filtered left_at, so
-- someone who LEFT a team kept receiving that team's join-request and
-- guest-claim notifications - and since the row is addressed to them they could
-- read who is trying to join their old club, indefinitely.

select tests.create_supabase_user('boss@n.dev');
select tests.create_supabase_user('exadmin@n.dev');
select tests.create_supabase_user('hopeful@n.dev');

select tests.authenticate_as('boss@n.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('boss@n.dev'), 'Boss');
select public.create_team('Notify XI', 'Pune') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset

select tests.authenticate_as('exadmin@n.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('exadmin@n.dev'), 'ExAdmin');
select public.accept_invite(:'_tok'::text) as _exm \gset
select tests.authenticate_as('boss@n.dev');
select public.set_team_member_role(:'_exm'::uuid, 'admin'::public.team_member_role);

-- give them history so leaving TOMBSTONES rather than deletes
select public.create_team('Notify Foes', 'Pune') as _o \gset
select public.add_guest_member(:'_o'::uuid, 'NF1') as _nf1 \gset
select public.add_guest_member(:'_o'::uuid, 'NF2') as _nf2 \gset
select public.add_guest_member(:'_t'::uuid, 'NB1') as _nb1 \gset
select public.create_match(:'_t'::uuid, :'_o'::uuid, 5) as _m \gset
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_exm'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_t'::uuid, :'_nb1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_nf1'::uuid);
select public.add_squad_member(:'_m'::uuid, :'_o'::uuid, :'_nf2'::uuid);

select public.leave_team(:'_exm'::uuid);
select isnt((select left_at from public.team_members where id = :'_exm'::uuid), null,
  'the ex-admin is tombstoned, not deleted');

-- someone asks to join the team
select tests.authenticate_as('hopeful@n.dev');
insert into public.profiles(id, display_name) values (tests.get_supabase_uid('hopeful@n.dev'), 'Hopeful');
select public.request_to_join(:'_t'::uuid);

reset role;
-- 2. the present captain IS told
select is(
  (select count(*)::int from public.notifications
    where recipient_id = tests.get_supabase_uid('boss@n.dev')
      and type = 'join_request'),
  1, 'the present captain is notified');

-- 3. THE BUG: the departed admin must NOT be
select is(
  (select count(*)::int from public.notifications
    where recipient_id = tests.get_supabase_uid('exadmin@n.dev')
      and type = 'join_request'),
  0, 'someone who left the team is not notified about it');

-- 4. and the same for a guest claim
select tests.authenticate_as('hopeful@n.dev');
select public.request_guest_claim(:'_nb1'::uuid);
reset role;
select is(
  (select count(*)::int from public.notifications
    where recipient_id = tests.get_supabase_uid('exadmin@n.dev')
      and type = 'claim_request'),
  0, 'nor about a guest claim on their old team');

select * from finish();
rollback;
