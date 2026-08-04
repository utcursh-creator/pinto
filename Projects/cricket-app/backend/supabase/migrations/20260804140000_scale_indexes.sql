-- Whole-system review #2 (2026-07-28), findings 20 / 21 / 29 / 60: the queries
-- on the app's hottest paths have no index that can serve them, so each one is
-- a full scan of its table. None of this is visible on a demo database with
-- thirty rows; all of it bites at exactly the point the app starts working.
--
-- Each index below is pinned by pgTAP 128, which asserts the PLANNER can
-- actually use it for the real predicate - not merely that the index exists.
-- That distinction is the whole point for the search case: no btree can serve
-- an unanchored ILIKE, so "there is an index on display_name" would have been
-- a comforting and useless assertion.

-- 20. Player/team search is `ilike '%q%'` on profiles.display_name,
--     profiles.handle and teams.name - unanchored, so the existing btree on
--     lower(handle) cannot help and every keystroke seq-scans both tables.
--     (The finding also claimed "no limit"; that half is REFUTED - both search
--     RPCs already cap at 15 and 25.)
create extension if not exists pg_trgm with schema "extensions";

create index if not exists profiles_display_name_trgm_idx
  on public.profiles using gin (display_name extensions.gin_trgm_ops);
create index if not exists profiles_handle_trgm_idx
  on public.profiles using gin (handle extensions.gin_trgm_ops);
create index if not exists teams_name_trgm_idx
  on public.teams using gin (name extensions.gin_trgm_ops);

-- 21. The public "Watch live" list filters status in ('live','innings_break')
--     and sorts by created_at desc. It is reachable WITHOUT SIGNING IN, so it
--     is the most exposed query in the app, and it seq-scanned and sorted the
--     entire matches table on every open.
--
--     Partial, because live matches are a vanishing fraction of all matches
--     ever played - the index stays small forever while the table grows, and
--     it carries created_at so the sort comes for free.
create index if not exists matches_live_created_idx
  on public.matches (created_at desc)
  where status in ('live', 'innings_break');

-- 60. Every team-scoped match query ("this club's fixtures", "have we played
--     them before") filtered on team_a_id or team_b_id with no index on
--     either.
create index if not exists matches_team_a_idx on public.matches (team_a_id);
create index if not exists matches_team_b_idx on public.matches (team_b_id);

-- 29. Career stats walk match_squad by team_member_id. The only index
--     mentioning that column is the composite UNIQUE (match_id,
--     team_member_id), where it is the SECOND column - useless for a lookup
--     that does not also know the match. So every player profile view scanned
--     the whole squad table.
create index if not exists match_squad_member_idx
  on public.match_squad (team_member_id);
