begin;
select plan(7);
-- Whole-system review #2 (2026-07-28), finding 54: a guest who has played for
-- the club and been removed can never be put in a match again.
--
-- leave_team TOMBSTONES a member with match history rather than deleting them,
-- because match_squad and deliveries reference the membership id. The squad
-- picker filters `left_at is null`, so the captain cannot select the old row -
-- and add_match_guest's duplicate-name check ignored left_at, so typing the
-- name was refused as "already on the team". Both doors shut on the same
-- player.
--
-- Ravi turns up again on a Sunday and simply cannot be picked.

select tests.create_supabase_user('cap@rg.dev');
select tests.authenticate_as('cap@rg.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@rg.dev'),'Cap');
select public.create_team('Sunday XI','Pune') as _t \gset
select public.create_team('Foes','Pune')     as _o \gset
select public.add_guest_member(:'_o'::uuid,'F1') as _f1 \gset
select public.add_guest_member(:'_o'::uuid,'F2') as _f2 \gset

-- Ravi plays a match, so removing him leaves a tombstone rather than a delete
select public.add_guest_member(:'_t'::uuid,'Ravi') as _ravi \gset
select public.add_guest_member(:'_t'::uuid,'Other') as _other \gset
select public.create_match(:'_t'::uuid,:'_o'::uuid,20) as _m1 \gset
select public.add_squad_member(:'_m1'::uuid,:'_t'::uuid,:'_ravi'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_t'::uuid,:'_other'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_o'::uuid,:'_f1'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_o'::uuid,:'_f2'::uuid);

select public.leave_team(:'_ravi'::uuid);
select is(
  (select count(*)::int from public.team_members
    where id = :'_ravi'::uuid and left_at is not null),
  1, 'Ravi is a tombstone, not a delete - his match history references him');

-- weeks later, a new match, and Ravi turns up
select public.create_match(:'_t'::uuid,:'_o'::uuid,20) as _m2 \gset

-- 2. THE BUG: the captain types his name and is refused
select lives_ok(
  format($$ select public.add_match_guest(%L, %L, 'Ravi') $$, :'_m2', :'_t'),
  'the captain can add Ravi to the new match - the picker cannot show him '
  'because it filters tombstones, so this was the only door and it was shut');

-- 3. it is the SAME row, so his career is not split in two
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid and lower(guest_name) = 'ravi'),
  1, 'and it is the same membership - one Ravi, with the innings he played '
     'still attached');
select is(
  (select count(*)::int from public.team_members
    where id = :'_ravi'::uuid and left_at is null),
  1, 'the tombstone is revived rather than a second row created');

-- 4. his old match still names him
select is(
  (select count(*)::int from public.match_squad
    where match_id = :'_m1'::uuid and team_member_id = :'_ravi'::uuid),
  1, 'the match he played still names the same membership');

-- 5. CONTROL: an ACTIVE duplicate is still refused. Dropping the check
--    entirely would let a captain fill a roster with copies of one name.
select throws_ok(
  format($$ select public.add_match_guest(%L, %L, 'Other') $$, :'_m2', :'_t'),
  'P0001', 'a guest with this name is already on the team',
  'a guest who is still on the roster cannot be added twice');

-- 6. CONTROL: a genuinely new name still creates a new membership
select public.add_match_guest(:'_m2'::uuid, :'_t'::uuid, 'Newcomer') as _new \gset
select isnt(:'_new'::uuid, :'_ravi'::uuid,
  'a name nobody has used gets a fresh membership');

select * from finish();
rollback;
