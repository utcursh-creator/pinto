-- Whole-system review #2 (2026-07-28), finding 43: an expired post still reads
-- as 'open' to its author, with no expiry shown and no way to renew.
--
-- discover_posts filters `expires_at > now()` AND `match_at >= now() - 6 hours`,
-- so the morning after a Saturday game the ad is invisible to everybody else.
-- My posts renders a status chip saying 'open' plus Mark filled / Cancel, and
-- nothing in the app has ever read or written expires_at - so the author is
-- told their ad is live, sees no replies, and can only guess that it died. The
-- only way back into the feed was to notice, and post again.
--
-- renew_post is the verb that was missing. Two deliberate refusals:
--
--   * a CANCELLED or FILLED post cannot be renewed. Those are decisions the
--     author made; renew is for an ad that ran out, not an undo.
--   * a post whose match date has already passed must be given a NEW date.
--     Pushing expires_at alone would leave it filtered out by the match-date
--     floor - back in the same silence, which is the bug.
create or replace function public.renew_post(
  _post_id uuid,
  _match_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare _row public.looking_for_posts;
begin
  select * into _row from public.looking_for_posts where id = _post_id;
  if _row.id is null then
    raise exception 'post not found' using errcode = 'P0001';
  end if;
  if _row.author_id <> (select auth.uid()) then
    raise exception 'not your post' using errcode = 'P0001';
  end if;
  if _row.status <> 'open' then
    raise exception 'only an open post can be renewed' using errcode = 'P0001';
  end if;
  if _match_at is null and _row.match_at is not null
     and _row.match_at < now() - interval '6 hours' then
    raise exception 'give this post a new date' using errcode = 'P0001';
  end if;

  update public.looking_for_posts
     set match_at = coalesce(_match_at, match_at),
         -- a dated ad dies the day after that game; an undated one gets the
         -- same fortnight a new post would get
         expires_at = case
           when coalesce(_match_at, match_at) is not null
             then coalesce(_match_at, match_at) + interval '1 day'
           else now() + interval '14 days'
         end
   where id = _post_id;
end; $function$;

revoke all on function public.renew_post(uuid, timestamptz) from public;
grant execute on function public.renew_post(uuid, timestamptz) to authenticated;
