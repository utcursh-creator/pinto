import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/core/auth/profile_provider.dart';

/// Whole-system review #2 (2026-07-28), finding 11 (HIGH): a failed background
/// profile re-read evicts a scorer mid-innings and drops them on Discover.
///
/// supabase_flutter refreshes the JWT about an hour in and on every resume from
/// background, so currentSessionProvider yields a new Session and
/// myProfileProvider re-runs `rpc('my_profile')`. At a ground with bad signal
/// that one call fails. `skipLoadingOnReload` closed the LOADING branch (the
/// CRITICAL fixed in the 2026-07-07 run) but `when()` defaults skipError to
/// false, so the ERROR branch fired even though the gate was still holding a
/// perfectly good profile. Both branches share the same line in the router:
///
///     return loc == Routes.splash ? null : Routes.splash;
///
/// - so the whole stack is replaced with /splash, a top-level route outside the
/// tab shell. The console, the selected bowler and any half-entered wicket
/// dialog are gone, and tapping Retry lands on Discover, not back in the match.
/// The same trigger fires from Edit profile's invalidate on save.
///
/// A re-read that fails while we already know who the user is changes nothing.
/// A FIRST read that fails is a genuine unknown and still holds on splash.
final _session = Session(
  accessToken: 'token',
  tokenType: 'bearer',
  user: User(
    id: 'me',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class _Boom implements Exception {
  @override
  String toString() => 'Exception: no signal';
}

/// Keeps the gate (and through it the profile) subscribed, then waits for the
/// read to land. `container.read(...future)` alone leaves nothing listening, so
/// the element is torn down mid-flight and the future never answers.
///
/// It takes the LOAD rather than a list of overrides because riverpod 3's
/// `Override` type is not nameable from a test file (documented project
/// gotcha), so the list cannot be hoisted into a helper's parameter.
ProviderContainer _live(Future<Map<String, dynamic>?> Function() load) {
  final c = ProviderContainer(overrides: [
    currentSessionProvider.overrideWithValue(_session),
    myProfileProvider.overrideWith((ref) => load()),
  ]);
  c.listen(authGateProvider, (_, _) {}, fireImmediately: true);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  for (var i = 0; i < 50 && c.read(myProfileProvider).isLoading; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a failed profile RE-read leaves an onboarded user exactly where they '
      'are', () async {
    var fail = false;
    final container = _live(() async {
      if (fail) throw _Boom();
      return {'id': 'me', 'display_name': 'Scorer'};
    });
    addTearDown(container.dispose);

    await _settle(container);
    expect(container.read(authGateProvider), AuthGate.ready,
        reason: 'sanity: an onboarded user');

    // the JWT refreshes at the ground and the re-read dies
    fail = true;
    container.invalidate(myProfileProvider);
    await _settle(container);
    expect(container.read(myProfileProvider).hasError, isTrue,
        reason: 'sanity: the re-read really did fail');

    expect(container.read(authGateProvider), AuthGate.ready,
        reason: 'the gate is still holding a profile. Reporting error here '
            'sends the router the same "everything to /splash" answer the '
            'loading branch did, which tears down the tab shell and every '
            'branch navigator under it - mid-innings, with no way back');
  });

  test('CONTROL: a profile read that fails with nothing known still stops on '
      'the splash', () async {
    final container = _live(() async => throw _Boom());
    addTearDown(container.dispose);

    await _settle(container);
    expect(container.read(authGateProvider), AuthGate.error,
        reason: 'a cold start that cannot read the profile genuinely does not '
            'know whether this user has onboarded. Suppressing THAT would '
            'route them by guesswork - the retry screen is correct here');
  });

  test('CONTROL: a re-read that returns null still means needs-profile',
      () async {
    var row = <String, dynamic>{'id': 'me'};
    final container = _live(() async => row.isEmpty ? null : row);
    addTearDown(container.dispose);
    await _settle(container);
    expect(container.read(authGateProvider), AuthGate.ready);

    // a deleted account is a real answer, not a failure - it must still move
    row = {};
    container.invalidate(myProfileProvider);
    await _settle(container);
    expect(container.read(authGateProvider), AuthGate.needsProfile,
        reason: 'holding the previous value must apply to ERRORS only. A '
            'successful read saying "no profile" has to be obeyed');
  });
}
