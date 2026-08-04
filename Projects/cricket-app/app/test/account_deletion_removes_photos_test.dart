import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), finding 52: a deleted account's photos
/// stay in the public buckets, served at their original URLs, forever.
///
/// The database cannot fix this. Supabase rejects any direct DELETE on
/// storage.objects - "Direct deletion from storage tables is not allowed. Use
/// the Storage API instead" - deliberately, because removing the row would
/// orphan the underlying file rather than delete it. Verified by trying it in a
/// migration: the whole transaction aborted. So this half of the promise has to
/// be kept by the client, and the ORDER is the property that matters:
///
///   delete_my_account revokes the user's auth rows. After it runs, the Storage
///   API can no longer act as that user, so anything not already removed is
///   stranded in a public bucket permanently. Photos must go FIRST, and a
///   failure must NOT be swallowed - an account that is still there can be
///   deleted again tomorrow; a photo nobody can authenticate to delete cannot.
///
/// A source guard rather than a mocked run: the assertion is about the order of
/// two calls in a widget callback, and standing up a fake SupabaseClient plus a
/// fake StorageFileApi would be a large amount of machinery that still would not
/// check the thing this checks.
String _code(String path) => File(path)
    .readAsLinesSync()
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  const settings = 'lib/src/features/profile/presentation/settings_screen.dart';
  const repo = 'lib/src/features/identity/data/identity_repository.dart';

  test('photos are deleted BEFORE the account is', () {
    final src = _code(settings);
    final uploads = src.indexOf('deleteMyUploads()');
    final rpc = src.indexOf("rpc('delete_my_account')");

    expect(uploads, isNot(-1),
        reason: 'the deletion flow never removes the user\'s uploads, so their '
            'avatar and post photos stay publicly served forever');
    expect(rpc, isNot(-1),
        reason: 'anchor lost - this guard is no longer checking anything');
    expect(uploads, lessThan(rpc),
        reason: 'delete_my_account revokes the auth rows, so the Storage API '
            'cannot act as this user afterwards. Photos removed after it are '
            'stranded in a public bucket permanently.');
  });

  test('a failed photo delete stops the account deletion', () {
    final src = _code(settings);
    final uploads = src.indexOf('deleteMyUploads()');
    final rpc = src.indexOf("rpc('delete_my_account')");
    final between = src.substring(uploads, rpc);
    expect(between, isNot(contains('catch')),
        reason: 'swallowing a failed photo delete would let the account go '
            'while the pictures stay. An account still present can be deleted '
            'again; a photo whose owner no longer exists cannot.');
  });

  test('both public buckets are covered', () {
    final src = _code(repo);
    final at = src.indexOf('Future<void> deleteMyUploads()');
    expect(at, isNot(-1), reason: 'deleteMyUploads is gone');
    final body = src.substring(at, at + 700);
    expect(body, contains("'avatars'"));
    expect(body, contains("'post-images'"),
        reason: 'post photos are uploaded to a separate public bucket and are '
            'just as identifying as an avatar');
  });

  test('the dialog no longer promises less than it delivers', () {
    final src = File(settings).readAsStringSync();
    expect(src, contains('photos'),
        reason: 'the confirmation text lists what is removed; it said '
            '"profile, posts and messages" while deleting neither the messages '
            'nor the photos');
  });
}
