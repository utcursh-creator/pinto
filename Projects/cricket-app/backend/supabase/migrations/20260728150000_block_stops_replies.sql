-- HIGH (whole-system review #2): "Block user" only closed DMs.
--
-- The blocked person kept replying on the victim's looking-for posts - the most
-- public surface in the app, the one their whole neighbourhood reads. So the one
-- action a harassed user takes did almost nothing while appearing to work, which
-- is worse than no block: they stop looking for another remedy.
--
-- is_blocked_between() already exists and is already symmetric (it matches a row
-- in either direction), which is the right semantics - the blocker also does not
-- want to be dragged into the blocked person's threads.
--
-- The subtlety that cost a round trip: `looking_for_posts` is own-rows-only for
-- direct SELECT (posts are read through the discover_posts RPC, not the table),
-- so a policy subquery reading it as the INSERTING user returns NULL for anyone
-- else's post - and is_blocked_between(NULL) is false, so the guard would never
-- fire. The author lookup therefore has to be SECURITY DEFINER.

create or replace function public.post_author(_post_id uuid)
returns uuid language sql security definer set search_path = public stable as $$
  select author_id from public.looking_for_posts where id = _post_id;
$$;
revoke all on function public.post_author(uuid) from public;
grant execute on function public.post_author(uuid) to authenticated;

drop policy if exists "post_replies_insert_own" on public.post_replies;
drop policy if exists "post_replies_insert_unblocked" on public.post_replies;

create policy "post_replies_insert_unblocked"
  on public.post_replies for insert to authenticated
  with check (
    author_id = (select auth.uid())
    -- coalesce, not a bare NOT: a reply to a post that does not exist yields
    -- NULL, and `not NULL` is NULL, which would let the row through.
    and coalesce(
      not public.is_blocked_between(public.post_author(post_id)), false)
  );
