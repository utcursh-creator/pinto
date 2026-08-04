-- Whole-system review #2 (2026-07-28), finding 62: photo_url, image_urls and
-- logo_url are unvalidated client-supplied strings, which makes every one of
-- them a tracking beacon.
--
-- An attacker PATCHes their own profile row - profiles_update_own permits it,
-- and the column has no constraint - to point photo_url at a host they control.
-- They then join a public squad or a tournament. From that moment every screen
-- that draws them (roster, DM inbox, search, claim inbox, leaderboards, the
-- stats header) issues an unauthenticated GET to that host, handing over the
-- VIEWER's IP address, User-Agent and a timestamped read receipt of exactly who
-- looked. Because public_profile_minimal and player_public_profile return
-- photo_url to anon, and /player/:id, /watch/:id and /tournament/:id bypass the
-- auth gate, it fires for logged-out visitors who have no account and never
-- consented to anything.
--
-- THE FIX IS TO STOP STORING THE HOST. A URL is normalised on write to the
-- host-free path `/storage/v1/object/public/<bucket>/<name>`, and the client
-- resolves it against its OWN configured Supabase origin. The attacker cannot
-- choose a host that is no longer written down.
--
-- Checking the shape alone would have been theatre: anyone can serve
-- `https://attacker.example/storage/v1/object/public/avatars/x.png`. The object
-- must also EXIST in our storage, which the upload policies already confine to
-- the uploader's own `<uid>/` folder.

-- Returns the host-free canonical path for one of our storage URLs, or null if
-- the value does not name an object that actually exists in our buckets.
-- SECURITY DEFINER so the existence check is not itself subject to the
-- storage.objects read policy (a viewer may set a photo they can no longer
-- SELECT after an ownership change).
create or replace function public.normalised_storage_path(_url text)
returns text
language plpgsql
security definer
set search_path to ''
stable
as $function$
declare _rest text; _bucket text; _name text;
begin
  if _url is null or _url = '' then return null; end if;

  -- accept either an absolute URL of any host or an already-normalised path;
  -- everything after the marker is <bucket>/<name>
  _rest := substring(_url from '/storage/v1/object/public/(.*)$');
  if _rest is null then return null; end if;

  -- drop any query string or fragment a CDN may have appended
  _rest := split_part(split_part(_rest, '?', 1), '#', 1);
  _bucket := split_part(_rest, '/', 1);
  _name := substring(_rest from length(_bucket) + 2);
  if _bucket is null or _name is null or _name = '' then return null; end if;

  if not exists (
    select 1 from storage.objects o
     where o.bucket_id = _bucket and o.name = _name
  ) then
    return null;
  end if;

  return '/storage/v1/object/public/' || _bucket || '/' || _name;
end; $function$;

revoke all on function public.normalised_storage_path(text) from public;
grant execute on function public.normalised_storage_path(text) to authenticated, anon;

-- profiles.photo_url
create or replace function public.normalise_profile_photo()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  NEW.photo_url := public.normalised_storage_path(NEW.photo_url);
  return NEW;
end; $function$;

drop trigger if exists profiles_normalise_photo on public.profiles;
create trigger profiles_normalise_photo
  before insert or update of photo_url on public.profiles
  for each row execute function public.normalise_profile_photo();

-- teams.logo_url
create or replace function public.normalise_team_logo()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  NEW.logo_url := public.normalised_storage_path(NEW.logo_url);
  return NEW;
end; $function$;

drop trigger if exists teams_normalise_logo on public.teams;
create trigger teams_normalise_logo
  before insert or update of logo_url on public.teams
  for each row execute function public.normalise_team_logo();

-- looking_for_posts.image_urls (an array; anything that does not resolve is
-- dropped rather than nulling the whole post)
create or replace function public.normalise_post_images()
returns trigger language plpgsql security definer set search_path to '' as $function$
begin
  if NEW.image_urls is null then return NEW; end if;
  NEW.image_urls := (
    select coalesce(array_agg(p order by ord), '{}')
    from unnest(NEW.image_urls) with ordinality as u(raw, ord)
    cross join lateral (select public.normalised_storage_path(u.raw) as p) z
    where p is not null
  );
  return NEW;
end; $function$;

drop trigger if exists posts_normalise_images on public.looking_for_posts;
create trigger posts_normalise_images
  before insert or update of image_urls on public.looking_for_posts
  for each row execute function public.normalise_post_images();
