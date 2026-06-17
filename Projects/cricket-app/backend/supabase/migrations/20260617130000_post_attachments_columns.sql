-- Post attachments: photos (Storage URLs) + an optional link on a looking-for post.
alter table public.looking_for_posts
  add column image_urls text[] not null default '{}',
  add column link_url text;
