import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';

/// Builds a User the way Supabase actually returns it. Verified against the
/// hosted project: an anonymous user carries `is_anonymous: true` as a TOP-LEVEL
/// claim and leaves `app_metadata` EMPTY (`{}`). A real OAuth user has
/// `is_anonymous: false` and a populated `app_metadata` (provider/providers).
User _user({required bool isAnonymous, Map<String, dynamic>? appMetadata}) {
  return User.fromJson({
    'id': '00000000-0000-0000-0000-000000000001',
    'app_metadata': appMetadata ?? <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'aud': 'authenticated',
    'created_at': '2026-06-27T00:00:00.000Z',
    'is_anonymous': isAnonymous,
  })!;
}

Session _session(User user) =>
    Session(accessToken: 'token', tokenType: 'bearer', user: user);

void main() {
  test('null session is treated as anonymous', () {
    expect(isAnonymousSession(null), isTrue);
  });

  test('anonymous user (is_anonymous claim true, app_metadata empty) is anonymous', () {
    final session = _session(_user(isAnonymous: true));
    expect(isAnonymousSession(session), isTrue);
  });

  test('a real OAuth user is not anonymous', () {
    final session = _session(_user(
      isAnonymous: false,
      appMetadata: {
        'provider': 'google',
        'providers': ['google'],
      },
    ));
    expect(isAnonymousSession(session), isFalse);
  });
}
