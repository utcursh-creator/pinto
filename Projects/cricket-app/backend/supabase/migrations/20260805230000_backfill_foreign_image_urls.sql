-- Code review (2026-08-05): 20260804240000 normalises image URLs on WRITE and
-- never touched what was already stored.
--
-- normalised_storage_path returns NULL for anything that is not a
-- /storage/v1/object/public/<bucket>/<name> path naming a row that actually
-- exists in storage.objects. The triggers apply it to profiles.photo_url,
-- teams.logo_url and looking_for_posts.image_urls from that migration onward -
-- but a row written BEFORE it keeps whatever it had, and the client's
-- resolveStorageUrl passes any absolute URL straight through
-- (`if (!stored.startsWith('/')) return stored;`).
--
-- So a pre-existing external URL still renders, and every viewer - including
-- logged-out visitors on the public /watch and /player pages, who never agreed
-- to anything - sends their IP and User-Agent to that host on page load.
--
-- Checked hosted before writing this: 0 external photo_urls, 0 logo_urls, 0
-- post image_urls. This is a no-op there and closes the hole for every other
-- environment, and for any row that predates the trigger anywhere.
update public.profiles
   set photo_url = public.normalised_storage_path(photo_url)
 where photo_url is not null
   and public.normalised_storage_path(photo_url) is distinct from photo_url;

update public.teams
   set logo_url = public.normalised_storage_path(logo_url)
 where logo_url is not null
   and public.normalised_storage_path(logo_url) is distinct from logo_url;

-- image_urls is an array: normalise element-wise and drop what does not survive
update public.looking_for_posts p
   set image_urls = coalesce((
     select array_agg(n order by ord)
       from unnest(p.image_urls) with ordinality as u(raw, ord)
       cross join lateral (select public.normalised_storage_path(u.raw) as n) x
      where n is not null), '{}')
 where p.image_urls is not null
   and exists (
     select 1 from unnest(p.image_urls) as e(raw)
      where public.normalised_storage_path(e.raw) is distinct from e.raw);
