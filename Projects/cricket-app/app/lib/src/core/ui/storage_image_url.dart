import '../config/env.dart';

/// Resolves a stored image reference into a URL that can actually be fetched.
///
/// Image references are stored HOST-FREE - the path
/// `/storage/v1/object/public/BUCKET/NAME` - and the host comes from this
/// app's own configuration. That is the
/// whole point: photo_url, logo_url and image_urls used to be arbitrary
/// client-supplied strings, so anyone could point their avatar at a host they
/// controlled and turn every roster, inbox and leaderboard that drew them into
/// a beacon reporting the VIEWER's IP, User-Agent and the time they looked -
/// including logged-out visitors, since the public routes bypass the auth gate
/// and photo_url is returned to anon (review #2, finding 62).
///
/// A host that is never written down cannot be chosen by an attacker.
///
/// Returns null for null/empty so callers keep their "no photo" branch. An
/// absolute URL is passed through unchanged: rows written before the
/// normalising triggers existed still hold one, and the trigger has already
/// refused any that does not resolve to a real object in our storage.
String? resolveStorageUrl(String? stored) {
  if (stored == null || stored.isEmpty) return null;
  if (!stored.startsWith('/')) return stored;
  final base = SupabaseEnv.url.endsWith('/')
      ? SupabaseEnv.url.substring(0, SupabaseEnv.url.length - 1)
      : SupabaseEnv.url;
  return '$base$stored';
}
