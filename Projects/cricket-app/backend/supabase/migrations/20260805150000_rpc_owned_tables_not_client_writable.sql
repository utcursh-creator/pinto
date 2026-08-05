-- Review #3's THEME, not four of its findings: a table-level grant that makes an
-- RPC's guards decorative, and a grant lost when a function was recreated.
--
--   matches INSERT           an admin of ONE participating team could insert a
--                            match that was already 'complete' with a result
--                            they invented, bypassing the scoring engine and
--                            set_match_result. (Two STRANGER teams was always
--                            refused by RLS - that half of the finding was
--                            overstated, and I verified both by hand.)
--   team_members I/U/D       consent, the last-captain guard and the left_at
--                            tombstone all became optional: attach any profile
--                            to your roster, demote the last captain, hard-delete
--                            a member whose match history references them.
--   looking_for_posts UPDATE expires_at, status and geog were client-settable, so
--                            renew_post, cancel_post, mark_post_filled and the
--                            ~550m _snap_geog coarsening were all advisory.
--   discover_posts EXECUTE   20260804190000 dropped and recreated the function
--                            and never re-granted, leaving proacl NULL - which in
--                            Postgres is not "no access", it is PUBLIC, so anon
--                            could call the geo feed.
--
-- Review #2 fixed this exact shape for `deliveries` and `match_squad`. It came
-- back because nothing was watching. pgTAP 147 now watches: its last assertion
-- fails if any migration re-grants a client write on an RPC-owned table.
--
-- SAFE: the Flutter app writes none of these three tables directly - every path
-- already goes through an RPC. Grepped, not assumed.

revoke insert on public.matches from authenticated;
revoke insert, update, delete on public.team_members from authenticated;
revoke insert, update, delete on public.looking_for_posts from authenticated;

-- Not in any finding - the DRIFT GUARD in pgTAP 147 caught it while I was
-- writing the fix, which is the whole reason the guard exists. The app only ever
-- SELECTs tournaments; every write is an RPC (create_tournament,
-- generate_group_fixtures, generate_playoffs, advance_playoffs,
-- delete_my_account), so the grant was pure attack surface: an organiser could
-- have set status='complete' and named their own champion_team_id without
-- playing the bracket.
revoke insert, update, delete on public.tournaments from authenticated;

-- and the grant that went missing. authenticated only: the feed is the product,
-- and an anonymous visitor gets the login-free VIEWER, not other people's
-- whereabouts.
revoke all on function public.discover_posts(
  double precision, double precision, double precision, public.lf_mode, integer,
  timestamptz, public.skill_level, public.lf_flair, integer) from public;
grant execute on function public.discover_posts(
  double precision, double precision, double precision, public.lf_mode, integer,
  timestamptz, public.skill_level, public.lf_flair, integer) to authenticated;
