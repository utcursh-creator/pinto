begin;
select plan(10);
-- Sweep Unit A discovery roots: handle search (MISS-5), post ball_type (DISC-1),
-- invite-preview reasons (DISC-8), guest career profile (STAT-2).
select tests.create_supabase_user('sw@s.dev');
select tests.authenticate_as('sw@s.dev');
insert into public.profiles(id, display_name, handle)
  values (tests.get_supabase_uid('sw@s.dev'), 'Sweep Tester', 'sweeper42');

-- MISS-5: search matches the handle (with or without @) and returns it
select is(
  (select handle from public.search_players_and_teams('sweeper4') where kind = 'player' limit 1),
  'sweeper42', 'search finds a player by handle substring');
select is(
  (select name from public.search_players_and_teams('@sweeper42') where kind = 'player' limit 1),
  'Sweep Tester', 'a leading @ is accepted');

-- DISC-1: ball_type round-trips create -> feed -> detail
select public.create_looking_for_post(
  'player_seeking_team'::public.lf_mode, 'practice_match'::public.lf_flair,
  19.0760, 72.8777, _ball_type := 'tennis'::public.ball_type) as _p \gset
select is(
  (select ball_type::text from public.discover_posts(19.0760, 72.8777) where post_id = :'_p'::uuid),
  'tennis', 'discover_posts returns the ball type');
select is(public.post_detail(:'_p'::uuid)->>'ball_type', 'tennis',
  'post_detail returns the ball type');

-- DISC-8: preview says WHY a token is dead
select public.create_team('Inv', 'P') as _t \gset
select public.create_team_invite(:'_t'::uuid) as _tok \gset
select is(public.team_invite_preview(:'_tok'::text)->>'reason', null,
  'a live invite has no reason');
select is((public.team_invite_preview(:'_tok'::text)->>'redeemable')::boolean, true,
  'a live invite is redeemable');
update public.team_invites set expires_at = now() - interval '1 hour' where invite_token = :'_tok';
select is(public.team_invite_preview(:'_tok'::text)->>'reason', 'expired',
  'an expired invite says expired');
update public.team_invites set expires_at = now() + interval '1 day', status = 'expired'
  where invite_token = :'_tok';
select is(public.team_invite_preview(:'_tok'::text)->>'reason', 'revoked',
  'an admin-revoked invite says revoked');

-- STAT-2: a guest member gets a career destination keyed by member id
select public.add_guest_member(:'_t'::uuid, 'Guesty') as _g \gset
select is(public.guest_player_profile(:'_g'::uuid)->>'name', 'Guesty',
  'guest profile resolves the guest name');
select is(public.guest_player_profile(:'_g'::uuid)->>'team_name', 'Inv',
  'guest profile names the team');

select * from finish();
rollback;
