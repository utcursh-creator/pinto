begin;
select plan(8);
-- Review #3 (MEDIUM), finding 12: the OTHER "Add guest" button splits a
-- returning guest's career instead of reviving them.
--
-- There are two live, identically-labelled buttons for the same act:
--   * match squads screen -> add_match_guest, which REVIVES the tombstone
--     (fixed by 20260804260000, pinned by test 140), and
--   * team page          -> add_guest_member, which does not.
--
-- add_guest_member got the `and left_at is null` half of that fix
-- (20260707200000) and never got the revive. On its own that filter turns a
-- hard block into a SILENT SPLIT: the duplicate check no longer sees the
-- tombstone, so it inserts a second row of the same name. The guest career page
-- is keyed on team_members.id, and teamRosterProvider filters tombstones out, so
-- the returning player reads as brand new with zero matches while their real
-- record hangs off a row nothing in the app can reach.
--
-- And it is PERMANENT: with an active row of that name now present,
-- add_match_guest - the path that would have merged them - starts raising
-- 'a guest with this name is already on the team'. There is no un-tombstone verb.
--
-- Same person, same club, two buttons, opposite irreversible outcomes.

select tests.create_supabase_user('cap@tp.dev');
select tests.authenticate_as('cap@tp.dev');
insert into public.profiles(id,display_name)
  values (tests.get_supabase_uid('cap@tp.dev'),'Cap');
select public.create_team('Club A','Pune') as _t \gset
select public.create_team('Foes','Pune')   as _o \gset
select public.add_guest_member(:'_o'::uuid,'F1') as _f1 \gset
select public.add_guest_member(:'_o'::uuid,'F2') as _f2 \gset

-- Ravi plays, so removing him TOMBSTONES rather than deletes
select public.add_guest_member(:'_t'::uuid,'Ravi Kumar') as _ravi \gset
select public.add_guest_member(:'_t'::uuid,'Other')      as _other \gset
select public.create_match(:'_t'::uuid,:'_o'::uuid,20) as _m1 \gset
select public.add_squad_member(:'_m1'::uuid,:'_t'::uuid,:'_ravi'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_t'::uuid,:'_other'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_o'::uuid,:'_f1'::uuid);
select public.add_squad_member(:'_m1'::uuid,:'_o'::uuid,:'_f2'::uuid);
select public.leave_team(:'_ravi'::uuid);

select is(
  (select count(*)::int from public.team_members
    where id = :'_ravi'::uuid and left_at is not null),
  1, 'sanity: Ravi is a tombstone, because his match history references him');

-- NEXT SEASON. The captain re-adds him from the TEAM PAGE.
select public.add_guest_member(:'_t'::uuid,'Ravi Kumar') as _again \gset

-- 2-3. THE BUG: a second row, and the career splits down the middle
select is(
  (select count(*)::int from public.team_members
    where team_id = :'_t'::uuid and lower(guest_name) = 'ravi kumar'),
  1, 'ONE Ravi on the team, not two - the guest career page is keyed on '
     'team_members.id, so a second row means he reads as a debutant while '
     'every innings he played hangs off a row the app filters out');
select is(
  :'_again'::uuid, :'_ravi'::uuid,
  'and re-adding him returns his ORIGINAL membership - the same id the old '
  'scorecards and match_squad rows point at');

-- 4. the tombstone is actually revived, not merely matched
select is(
  (select count(*)::int from public.team_members
    where id = :'_ravi'::uuid and left_at is null),
  1, 'the tombstone is revived');

-- 5. his old match still names him, which is the whole reason the row survived
select is(
  (select count(*)::int from public.match_squad
    where match_id = :'_m1'::uuid and team_member_id = :'_ravi'::uuid),
  1, 'and the match he played still points at that membership');

-- 6. HE IS PICKABLE AGAIN, which is the whole point. Once revived he is an
--    ACTIVE member, so the squad PICKER shows him (it filters left_at is null)
--    and the captain selects him there. add_match_guest refusing him as a NEW
--    guest at that point is correct, not a residue of the bug - he is not a new
--    guest. Before the fix he was neither: the picker hid the tombstone and the
--    team page had made a second, historyless row.
select public.create_match(:'_t'::uuid,:'_o'::uuid,20) as _m2 \gset
select lives_ok(
  format($$ select public.add_squad_member(%L, %L, %L) $$, :'_m2', :'_t', :'_ravi'),
  'his ORIGINAL membership can be picked for the new match - the id the old '
  'scorecards already point at, so one career, not two');

-- 7. CONTROL: a genuinely new name is still an INSERT, not a revive
select public.add_guest_member(:'_t'::uuid,'Brand New') as _new \gset
select isnt(:'_new'::uuid, :'_ravi'::uuid,
  'a name nobody has used still creates a new membership');

-- 8. CONTROL: an ACTIVE duplicate is still refused. Reviving must not become a
--    licence to add the same live player twice.
select throws_ok(
  format($$ select public.add_guest_member(%L, 'Other') $$, :'_t'),
  'P0001', 'a guest with this name is already on the team',
  'an ACTIVE member of that name is still a clash');

select * from finish();
rollback;
