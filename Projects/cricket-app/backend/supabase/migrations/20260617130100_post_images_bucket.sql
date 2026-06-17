-- Storage bucket for post photos. Public read (feed images load via CDN, no
-- signed URL); uploads gated by RLS to the uploader's own <uid>/ folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'post-images',
  'post-images',
  true,
  5242880, -- 5 MiB, in bytes (raw SQL takes the integer, not '5mb')
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do nothing;

-- storage.objects already has RLS enabled by Supabase; only add policies.
create policy "post_images_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "post_images_public_read"
  on storage.objects for select to public
  using (bucket_id = 'post-images');

create policy "post_images_delete_own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
