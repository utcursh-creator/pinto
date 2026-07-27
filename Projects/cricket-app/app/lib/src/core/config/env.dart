import 'package:flutter/foundation.dart';

/// Build-time configuration. Override with `--dart-define SUPABASE_URL=...`
/// and `--dart-define SUPABASE_PUBLISHABLE_KEY=...` (or
/// `--dart-define-from-file=hosted_defines.json`). The defaults target the
/// LOCAL `supabase start` stack (the well-known local key is not a secret).
class SupabaseEnv {
  const SupabaseEnv._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// The local stack's publishable key (from `supabase status`). supabase_flutter
  /// 2.15 deprecated the legacy `anonKey` init param in favor of this.
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  /// Google OAuth client IDs for the native sign-in flow. Supplied at build
  /// time (`--dart-define GOOGLE_WEB_CLIENT_ID=... GOOGLE_IOS_CLIENT_ID=...`).
  /// Empty by default: until provisioned, the Google button reports "not
  /// configured" rather than crashing. See ../../../../oauth-provisioning.md.
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Whether native Google sign-in has the client IDs it needs on THIS platform.
  /// Android uses the registered Android OAuth client (package + SHA) plus the
  /// web client as `serverClientId`, so it only needs the web id. iOS also needs
  /// its own iOS client id (and the reversed-client-id in Info.plist).
  /// True when the build is still pointed at the LOCAL dev stack.
  static bool get isLocal =>
      url.contains('127.0.0.1') || url.contains('localhost') || url.contains('10.0.2.2');

  /// A release binary pointed at localhost cannot reach anything: every screen
  /// fails with a connection error and it looks like the app is broken. The
  /// hosted config is supplied by --dart-define-from-file, which is easy to
  /// forget - so refuse to run rather than ship a dead build
  /// (penetration review 2026-07-07).
  static void assertReleaseConfigured() {
    if (kReleaseMode && isLocal) {
      throw StateError(
        'Release build is pointed at the local Supabase stack ($url). '
        'Rebuild with --dart-define-from-file=hosted_defines.json.',
      );
    }
  }

  static bool get googleConfigured {
    if (googleWebClientId.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return googleIosClientId.isNotEmpty;
    }
    return true;
  }
}
