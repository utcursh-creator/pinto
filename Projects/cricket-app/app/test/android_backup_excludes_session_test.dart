import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Whole-system review #2 (2026-07-28), finding 37: Android Auto Backup is ON by
/// default, so the Supabase refresh token leaves the device.
///
/// supabase_flutter persists the session - including the REFRESH TOKEN - in
/// app-private storage. With Android's defaults that storage is copied into the
/// user's Google cloud backup and restored onto any device that recovers it.
///
/// A refresh token is not a password. It needs no second factor and is silently
/// exchangeable for access tokens until somebody revokes it. Nothing this app
/// stores is worth putting one into a third-party backup.
///
/// Since Android 12 there are TWO channels and `allowBackup="false"` only closes
/// the first, so both are asserted:
///   cloud-backup    - Google Drive
///   device-transfer - direct device-to-device copy during setup
///
/// A file guard because this is build configuration: it has no runtime surface
/// to exercise, and it silently reverts to the permissive default if anyone
/// regenerates the manifest.
void main() {
  const manifest = 'android/app/src/main/AndroidManifest.xml';
  const rules = 'android/app/src/main/res/xml/data_extraction_rules.xml';

  test('the manifest opts out of backup', () {
    final src = File(manifest).readAsStringSync();
    expect(src, contains('android:allowBackup="false"'),
        reason: 'Android defaults allowBackup to TRUE, so leaving it unset '
            'ships the signed-in user\'s refresh token to Google Drive');
    expect(src, contains('android:dataExtractionRules='),
        reason: 'on Android 12+ allowBackup alone does not stop a '
            'device-to-device transfer during setup');
  });

  test('the extraction rules exclude every domain, both channels', () {
    final f = File(rules);
    expect(f.existsSync(), isTrue,
        reason: '$rules is referenced by the manifest; without it the build '
            'fails or the reference silently does nothing');
    final src = f.readAsStringSync();

    for (final channel in ['cloud-backup', 'device-transfer']) {
      final start = src.indexOf('<$channel>');
      expect(start, isNot(-1), reason: '$channel is not configured at all');
      final block = src.substring(start, src.indexOf('</$channel>'));
      for (final domain in ['root', 'file', 'database', 'sharedpref']) {
        expect(block, contains('domain="$domain"'),
            reason: 'the session is written through shared preferences and '
                'app files, so $channel must exclude $domain - a partial '
                'exclusion still ships the token');
      }
    }
  });
}
