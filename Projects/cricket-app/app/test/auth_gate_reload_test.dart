import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// CRITICAL (fix-run re-review 2026-07-07): a token refresh wiped the whole
/// navigation stack.
///
/// `authGateProvider` is a SYNC Provider that watches the ASYNC
/// `myProfileProvider` and calls `.when(loading: () => AuthGate.loading, ...)`.
/// Riverpod's `when()` has `skipLoadingOnReload = false` by DEFAULT, so when a
/// provider rebuilds because a watched dependency changed, the loading branch
/// IS taken even though the previous value is still held.
///
/// About an hour into a session - or the first time the app is foregrounded
/// with a stale JWT - supabase_flutter auto-refreshes the token and emits
/// `tokenRefreshed`. gotrue's `Session ==` compares accessToken/refreshToken, so
/// `currentSessionProvider` yields a NEW session, `myProfileProvider` reloads,
/// and the gate flips ready -> loading. The router's refresh listenable then
/// re-runs the redirect, whose loading branch sends every non-public location to
/// /splash - a top-level route OUTSIDE the tab shell, so the shell and every
/// branch navigator are torn down. A scorer half way through an innings lands on
/// Discover having touched nothing.
///
/// This models exactly that: a value, then a dependency change, then the same
/// value again. The gate must never report `loading` once it has an answer.
///
/// It is invisible to every other test in the suite because the journeys and
/// widget tests finish long before a JWT expires.

/// Stands in for the session: changing it is what a token refresh does.
class _SessionTick extends Notifier<int> {
  @override
  int build() => 0;
  void refreshToken() => state = state + 1;
}

final _sessionTickProvider =
    NotifierProvider<_SessionTick, int>(_SessionTick.new);

/// Stands in for myProfileProvider - reloads whenever the session changes.
final _profileProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  ref.watch(_sessionTickProvider);
  // The real my_profile() is a network round trip; without a real gap the
  // reload resolves inside one microtask batch and the intermediate loading
  // state is never observable, which would make this test prove nothing.
  await Future<void>.delayed(const Duration(milliseconds: 5));
  return {'id': 'me'};
});

enum _Gate { loading, ready }

/// The shape of the real authGateProvider.
_Gate _gateFrom(AsyncValue<Map<String, dynamic>?> profile,
        {required bool skipLoadingOnReload}) =>
    profile.when(
      skipLoadingOnReload: skipLoadingOnReload,
      data: (_) => _Gate.ready,
      loading: () => _Gate.loading,
      error: (_, _) => _Gate.loading,
    );

void main() {
  Future<List<_Gate>> observe({required bool skipLoadingOnReload}) async {
    final gate = Provider<_Gate>((ref) => _gateFrom(
          ref.watch(_profileProvider),
          skipLoadingOnReload: skipLoadingOnReload,
        ));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <_Gate>[];
    container.listen<_Gate>(gate, (_, next) => seen.add(next),
        fireImmediately: true);

    await container.read(_profileProvider.future); // first load settles
    await Future<void>.delayed(Duration.zero);
    seen.clear(); // we only care about what a REFRESH does

    // the token refresh
    container.read(_sessionTickProvider.notifier).refreshToken();
    await container.read(_profileProvider.future);
    await Future<void>.delayed(Duration.zero);
    return seen;
  }

  test('a token refresh must not flip the gate back to loading', () async {
    final seen = await observe(skipLoadingOnReload: true);
    expect(
      seen,
      isNot(contains(_Gate.loading)),
      reason: 'the gate still holds a profile, so a background token refresh '
          'must not report loading - the router tears the whole stack down to '
          '/splash when it does',
    );
  });

  test('and the default really would have flipped it (guards the reason)',
      () async {
    // If this ever stops emitting loading, Riverpod changed its default and the
    // skipLoadingOnReload argument in auth_gate.dart can be revisited.
    final seen = await observe(skipLoadingOnReload: false);
    expect(seen, contains(_Gate.loading),
        reason: 'when() defaults skipLoadingOnReload to false; that default is '
            'what caused the bug');
  });
}
