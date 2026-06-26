-- Storage bucket for profile photos + team logos. Public read (avatars load via
-- CDN); uploads gated by RLS to the uploader's own <uid>/ folder (a team admin
-- uploads a logo under their own folder; teams.logo_url just stores the URL).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880, -- 5 MiB
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do nothing;

create policy "avatars_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars_public_read"
  on storage.objects for select to public
  using (bucket_id = 'avatars');

create policy "avatars_delete_own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
