-- LOW (penetration review 2026-07-07, storage bucket enumeration):
-- `post_images_public_read` and `avatars_public_read` granted SELECT on
-- storage.objects for the whole bucket to PUBLIC (role `-`, so anon included).
-- SELECT on storage.objects is what governs the LIST endpoint, which is a
-- different thing from fetching a file: it let anyone walk the complete
-- contents of both buckets. Object paths are `<user-uuid>/<file>`, so that is
-- also a full dump of every user id in the system, plus every image anyone ever
-- uploaded - including ones attached to a post they have since deleted.
--
-- Both buckets are `public = true`, and a public bucket serves
-- /object/public/<bucket>/<path> WITHOUT consulting RLS, so dropping these
-- policies leaves every <img> in the app working and closes the list endpoint.
-- The app only ever calls uploadBinary + getPublicUrl; nothing calls list().

drop policy if exists "post_images_public_read" on storage.objects;
drop policy if exists "avatars_public_read" on storage.objects;

-- An owner should still be able to see their own objects (that is what makes
-- the delete policy usable from a client that lists its own folder first).
create policy "post_images_read_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars_read_own"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
