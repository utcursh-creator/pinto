-- SEC-2: looking_for_posts stores the author's EXACT geog and was readable by any
-- authenticated user (using(true)), so a client could select geog directly and
-- defeat discover_posts' 100m coarsening (trilateration -> a person's home). Drop
-- the blanket read policy; authors may still read their OWN posts (for the
-- my-posts list + edits). Everyone else reads the feed only through the
-- SECURITY DEFINER discover_posts()/post_detail() RPCs, which never return geog.
drop policy if exists "posts_select_authenticated" on public.looking_for_posts;

create policy "posts_select_own" on public.looking_for_posts
  for select to authenticated
  using (author_id = (select auth.uid()));
