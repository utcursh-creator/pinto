-- Whole-system review #2 (2026-07-28), finding 15: the DM inbox downloads every
-- message body in every thread the user has, and the thread-id list travels in
-- a GET query string.
--
-- The client made three round-trips: the user's thread ids, the other
-- participant of each, then EVERY MESSAGE of all of them - body included -
-- purely to take the first as a preview and count the unread ones. A long
-- conversation is thousands of rows, and it is re-fetched from scratch on every
-- inbox open, every incoming message and every pull-to-refresh. The
-- `.inFilter('thread_id', ids)` also puts the whole id list in the URL, which
-- has a length limit that grows with the user's popularity.
--
-- One call, one row per thread, and no message body crosses the wire except the
-- preview that is actually displayed.
create or replace function public.dm_inbox()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
as $function$
  with me as (select (select auth.uid()) as uid),
  mine as (
    select p.thread_id from public.dm_participants p, me
     where p.profile_id = me.uid
  ),
  other as (
    select p.thread_id,
           jsonb_build_object('id', pr.id, 'display_name', pr.display_name,
                              'photo_url', pr.photo_url) as who
      from public.dm_participants p
      join mine on mine.thread_id = p.thread_id
      join public.profiles pr on pr.id = p.profile_id, me
     where p.profile_id <> me.uid
  ),
  last_msg as (
    -- DISTINCT ON is the point: one row per thread instead of all of them
    select distinct on (m.thread_id)
           m.thread_id, m.body, m.created_at
      from public.dm_messages m
      join mine on mine.thread_id = m.thread_id
     order by m.thread_id, m.created_at desc
  ),
  unread as (
    select m.thread_id, count(*)::int as n
      from public.dm_messages m
      join mine on mine.thread_id = m.thread_id, me
     where m.sender_id <> me.uid and m.read_at is null
     group by m.thread_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'thread_id', mine.thread_id,
           'other', other.who,
           'preview', last_msg.body,
           'last_at', last_msg.created_at,
           'unread', coalesce(unread.n, 0))
         -- most recent conversation first; threads with no messages sink
         order by last_msg.created_at desc nulls last), '[]'::jsonb)
    from mine
    left join other    on other.thread_id    = mine.thread_id
    left join last_msg on last_msg.thread_id = mine.thread_id
    left join unread   on unread.thread_id   = mine.thread_id;
$function$;

revoke all on function public.dm_inbox() from public;
grant execute on function public.dm_inbox() to authenticated;
