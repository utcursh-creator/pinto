import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/config/env.dart';
import 'package:pitch_app/src/core/ui/storage_image_url.dart';

/// Whole-system review #2 (2026-07-28), finding 62 - the client half.
///
/// Image references are stored HOST-FREE, because a host that is never written
/// down cannot be chosen by an attacker. This resolves them against the app's
/// OWN configured origin, which is what makes the stored form usable.
void main() {
  test('a stored path resolves against our own configured origin', () {
    const path = '/storage/v1/object/public/avatars/u/1.jpg';
    expect(resolveStorageUrl(path), '${SupabaseEnv.url}$path',
        reason: 'the host comes from this build, never from the database');
  });

  test('null and empty keep the caller\'s "no photo" branch', () {
    expect(resolveStorageUrl(null), isNull);
    expect(resolveStorageUrl(''), isNull);
  });

  test('an absolute URL is passed through unchanged', () {
    // Rows written before the normalising trigger existed still hold one, and
    // the trigger has already refused any that does not resolve to a real
    // object in our storage.
    const abs = 'http://127.0.0.1:54321/storage/v1/object/public/avatars/u/1.jpg';
    expect(resolveStorageUrl(abs), abs);
  });

  test('a trailing slash on the configured origin does not double up', () {
    // SupabaseEnv.url is build-time config and a trailing slash is an easy
    // thing to paste; '//storage/...' would 404 on every avatar in the app.
    expect(resolveStorageUrl('/storage/v1/object/public/avatars/u/1.jpg'),
        isNot(contains('//storage')));
  });
}
