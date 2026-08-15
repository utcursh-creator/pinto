begin;
select plan(5);
-- Code review, 2026-08-05: the revive block added by 20260804260000
-- (add_match_guest) and copied into 20260805190000 (add_guest_member) updates
-- EVERY tombstoned row matching the name:
--
--   update public.team_members set left_at = null
--    where team_id = _team_id and lower(guest_name) = lower(_name) ...
--   returning id into _id;
--
-- The review predicted a silent two-active-rows split. It is worse and louder:
-- plpgsql's `RETURNING ... INTO` is STRICT for multiple rows, so the call dies
-- with `query returned more than one row` and the whole transaction aborts.
-- "Add guest player" then fails permanently for that team + name, with a raw
-- Postgres error in the UI and no way round it.
--
-- Reachable from legacy data: the OLD add_guest_member inserted a duplicate row
-- instead of reviving (that was the bug 20260805190000 fixed), so any team that
-- accumulated two same-named guests before the fix, and lost both, is now in
-- this state. Hosted currently has 0 such teams - this is latent, not live.
select tests.create_supabase_user('rv1@t.dev');
select tests.authenticate_as('rv1@t.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rv1@t.dev'),'Cap');
select public.create_team('Revive XI','Pune') as _t \gset

select current_role as _r \gset
set local role postgres;
insert into public.team_members(team_id, guest_name, left_at, claimable)
values (:'_t'::uuid,'Ravi', now() - interval '10 days', true),
       (:'_t'::uuid,'Ravi', now() - interval '1 day',  true);
set local role :_r;

select is((select count(*)::int from public.team_members
            where team_id = :'_t'::uuid and left_at is not null), 2,
  'sanity: two tombstoned rows of one name, the legacy shape');

-- 2. it must SUCCEED, not raise
select lives_ok(
  format($$ select public.add_guest_member(%L, 'Ravi') $$, :'_t'),
  'adding the guest back does not blow up on two tombstones');

-- 3-4. exactly ONE row comes back to life; the other stays a tombstone
select is((select count(*)::int from public.team_members
            where team_id = :'_t'::uuid and lower(guest_name)='ravi' and left_at is null), 1,
  'exactly one row is revived - two would be the very split this revive exists '
  'to prevent, and would then block add_match_guest for good');
select is((select count(*)::int from public.team_members
            where team_id = :'_t'::uuid and lower(guest_name)='ravi' and left_at is not null), 1,
  'and the older tombstone is left alone rather than silently resurrected');

-- 5. the SAME shape in add_match_guest, which the revive was copied from
select public.create_team('Revive B','Pune') as _t2 \gset
select public.create_match(:'_t'::uuid, :'_t2'::uuid, 20) as _m \gset
set local role postgres;
insert into public.team_members(team_id, guest_name, left_at, claimable)
values (:'_t2'::uuid,'Sunil', now() - interval '9 days', true),
       (:'_t2'::uuid,'Sunil', now() - interval '2 days', true);
set local role :_r;
select lives_ok(
  format($$ select public.add_match_guest(%L, %L, 'Sunil') $$, :'_m', :'_t2'),
  'add_match_guest has the same unbounded revive and must survive it too');

select * from finish();
rollback;
