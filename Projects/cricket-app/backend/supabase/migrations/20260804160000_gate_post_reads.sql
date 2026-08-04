-- Whole-system review #2 (2026-07-28), finding 63: post_replies is globally
-- readable and post_detail is ungated, so any account can build a permanent
-- index of who is looking for a game, roughly where, and with whom.
--
--   GET /rest/v1/post_replies?select=post_id,author_id,body   returns EVERY
--   reply ever written, to any post, anywhere - because
--   post_replies_select_authenticated is `using (true)` on top of a table-wide
--   SELECT grant. That is the free-text field where people actually type
--   "I'm in, ring me on 98xxxxxxxx" and "we play behind the Shivaji Park gate
--   at 6.30", each joined to its author.
--
--   Then POST /rest/v1/rpc/post_detail for each post_id resolves it to a title,
--   a place_label, a match time, the author's display name and the team name.
--   post_detail is SECURITY DEFINER and its entire WHERE clause is
--   `p.id = _post_id` - no distance, status, expiry or author check.
--
-- The asymmetry is what makes this a defect rather than a decision: the same
-- hardening run that hid the exact geography and put post reads behind definer
-- RPCs (20260702170000) left the replies table and the by-id resolver open, so
-- the side door outlived the front-door lock. discover_posts clamps the radius
-- to 50 km, requires status = 'open', drops expired posts and drops matches
-- more than six hours stale; none of that applied here.

-- One definition of "may this account see this post", used by both the RPC and
-- the policy. Two copies of one rule is how the bowler-quota bug happened
-- earlier in this same review.
--
-- SECURITY DEFINER so it can read looking_for_posts (whose blanket read was
-- deliberately revoked by SEC-2) and post_replies without recursing into the
-- very policy it is about to be used by.
--
-- coalesce(..., false): a missing post must be INVISIBLE, not NULL. A bare NULL
-- would make the policy neither true nor false and the guard would not fire -
-- the fourth time this codebase has been bitten by that shape.
create or replace function public.post_is_visible(_post_id uuid)
returns boolean
language sql
security definer
set search_path to 'public'
stable
as $function$
  select coalesce((
    select
      -- your own ad, forever - you must be able to review it after it closes
      p.author_id = (select auth.uid())
      -- or it is live, on exactly the terms the feed uses
      or (p.status = 'open'
          and (p.expires_at is null or p.expires_at > now())
          and (p.match_at is null or p.match_at >= now() - interval '6 hours'))
      -- or you are already in the conversation: someone who replied keeps
      -- access to the thread after the ad closes, or the app would erase a
      -- conversation they are part of
      or exists (select 1 from public.post_replies r
                  where r.post_id = p.id and r.author_id = (select auth.uid()))
    from public.looking_for_posts p
    where p.id = _post_id
  ), false);
$function$;

revoke all on function public.post_is_visible(uuid) from public;
grant execute on function public.post_is_visible(uuid) to authenticated;

-- The by-id resolver now answers only for posts the caller may see.
create or replace function public.post_detail(_post_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  select jsonb_build_object(
    'id', p.id, 'author_id', p.author_id, 'team_id', p.team_id,
    'mode', p.mode, 'flair', p.flair, 'title', p.title, 'description', p.description,
    'place_label', p.place_label, 'match_at', p.match_at, 'overs', p.overs,
    'skill', p.skill, 'slots_needed', p.slots_needed, 'status', p.status,
    'image_urls', p.image_urls, 'link_url', p.link_url, 'ball_type', p.ball_type,
    'author_name', pr.display_name, 'team_name', t.name)
  from public.looking_for_posts p
  left join public.profiles pr on pr.id = p.author_id
  left join public.teams t on t.id = p.team_id
  where p.id = _post_id
    and public.post_is_visible(p.id);
$function$;

-- And replies are readable only in the context of a post you may see.
drop policy if exists "post_replies_select_authenticated" on public.post_replies;
create policy "post_replies_select_visible"
  on public.post_replies for select to authenticated
  using (public.post_is_visible(post_id));
