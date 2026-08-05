begin;
select plan(9);
-- Review #3 (LOW), finding 23: a guest claim can be approved but never
-- declined, so a bogus claim sits in the captain's inbox forever.
--
-- Approving a claim rewrites team_members.profile_id - it hands over that
-- guest's entire batting and bowling history to the claimer. So a stranger who
-- taps "This is me" on a public team page is asking for someone's career, and
-- the captain's only control was an Approve button. No Decline, no dismiss, no
-- swipe. The row stays 'pending' and reappears on every visit to the inbox; the
-- requester cannot withdraw it either.
--
-- The 'rejected' status already existed in the enum and was only ever written
-- as a SIDE EFFECT of approving a COMPETING claim, so the single-claim case -
-- the common one - had no terminal state at all.
--
-- THE TRADE, stated rather than hidden: request_guest_claim reopens a rejected
-- row (its on-conflict only refuses when the status is 'approved'), so a
-- declined claimer can ask again. That is deliberate. Making a decline
-- permanent would mean one mis-tap locks the REAL player out of their own
-- record forever, with no admin path back - approve_guest_claim needs a pending
-- row to work on. Clearing the inbox is what the finding is about; a determined
-- re-requester is a rate-limiting problem, not this one.

select tests.create_supabase_user('cap@gc.dev');
select tests.create_supabase_user('rando@gc.dev');
select tests.create_supabase_user('other@gc.dev');

select tests.authenticate_as('rando@gc.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('rando@gc.dev'),'Rando');
select tests.authenticate_as('other@gc.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('other@gc.dev'),'Other');
select tests.authenticate_as('cap@gc.dev');
insert into public.profiles(id,display_name) values (tests.get_supabase_uid('cap@gc.dev'),'Cap');

select public.create_team('Claim XI','Pune') as _t \gset
select public.add_guest_member(:'_t'::uuid,'Ravi') as _mem \gset
select tests.get_supabase_uid('rando@gc.dev') as _rando \gset
select tests.get_supabase_uid('other@gc.dev') as _other \gset

-- a stranger asks for Ravi's identity
select tests.authenticate_as('rando@gc.dev');
select public.request_guest_claim(:'_mem'::uuid);
select tests.authenticate_as('cap@gc.dev');
select is(
  (select status::text from public.guest_claim_requests
    where membership_id = :'_mem'::uuid and requested_by = :'_rando'::uuid),
  'pending', 'sanity: the claim is sitting in the captain''s inbox');

-- 2. THE FIX: the captain can say no
select lives_ok(
  format($$ select public.decline_guest_claim(%L, %L) $$, :'_mem', :'_rando'),
  'the captain can decline a claim - approving it would have handed over every '
  'innings that guest has played');
select is(
  (select status::text from public.guest_claim_requests
    where membership_id = :'_mem'::uuid and requested_by = :'_rando'::uuid),
  'rejected', 'and it leaves the inbox, which filters on pending');

-- 3. declining must NOT touch the roster. This is the whole risk of adding a
--    second verb next to one that rewrites profile_id.
select is(
  (select count(*)::int from public.team_members
    where id = :'_mem'::uuid and profile_id is null and guest_name = 'Ravi'),
  1, 'the membership is untouched - still a guest, still named Ravi');

-- 4. and it cannot be declined twice
select throws_ok(
  format($$ select public.decline_guest_claim(%L, %L) $$, :'_mem', :'_rando'),
  'P0001', 'no pending claim from this user',
  'a claim already dealt with cannot be declined again');

-- 5. AUTHORIZATION: only an admin of THIS team. A decline is a decision about
--    somebody else's cricket record.
select tests.authenticate_as('other@gc.dev');
select public.request_guest_claim(:'_mem'::uuid);
select throws_ok(
  format($$ select public.decline_guest_claim(%L, %L) $$, :'_mem', :'_other'),
  'P0001', 'not authorized',
  'a stranger cannot decline - not even their own claim, which would let '
  'anyone probe which memberships exist');

-- 6. the captain can still APPROVE a different claim afterwards: declining one
--    request must not poison the membership.
select tests.authenticate_as('cap@gc.dev');
select lives_ok(
  format($$ select public.approve_guest_claim(%L, %L) $$, :'_mem', :'_other'),
  'a later, genuine claim can still be approved');
select is(
  (select profile_id from public.team_members where id = :'_mem'::uuid),
  :'_other'::uuid, 'and the membership transfers to them');

-- 7. THE TRADE, pinned so it is a decision and not an accident: a declined
--    claimer may ask again. If this ever becomes false, one mis-tap locks the
--    real player out of their own record permanently.
select public.create_team('Claim II','Pune') as _t2 \gset
select public.add_guest_member(:'_t2'::uuid,'Sunil') as _mem2 \gset
select tests.authenticate_as('rando@gc.dev');
select public.request_guest_claim(:'_mem2'::uuid);
select tests.authenticate_as('cap@gc.dev');
select public.decline_guest_claim(:'_mem2'::uuid, :'_rando'::uuid);
select tests.authenticate_as('rando@gc.dev');
select public.request_guest_claim(:'_mem2'::uuid);
select tests.authenticate_as('cap@gc.dev');
select is(
  (select status::text from public.guest_claim_requests
    where membership_id = :'_mem2'::uuid and requested_by = :'_rando'::uuid),
  'pending', 'a declined claimer can ask again - deliberate: a decline that '
             'were final would let one mis-tap lock the real player out of '
             'their own record, with no way back');

select * from finish();
rollback;
