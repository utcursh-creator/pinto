-- SEC-2 / DISC-5: the post-detail read now goes through a SECURITY DEFINER RPC
-- that returns everything the detail screen needs - including the author's name
-- and team name (DISC-5) - but NEVER the geog, only the human place_label. This
-- replaces the app's direct select on looking_for_posts.
create or replace function public.post_detail(_post_id uuid)
returns jsonb language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'id', p.id, 'author_id', p.author_id, 'team_id', p.team_id,
    'mode', p.mode, 'flair', p.flair, 'title', p.title, 'description', p.description,
    'place_label', p.place_label, 'match_at', p.match_at, 'overs', p.overs,
    'skill', p.skill, 'slots_needed', p.slots_needed, 'status', p.status,
    'image_urls', p.image_urls, 'link_url', p.link_url,
    'author_name', pr.display_name, 'team_name', t.name)
  from public.looking_for_posts p
  left join public.profiles pr on pr.id = p.author_id
  left join public.teams t on t.id = p.team_id
  where p.id = _post_id;
$$;
revoke all on function public.post_detail(uuid) from public;
grant execute on function public.post_detail(uuid) to authenticated;
