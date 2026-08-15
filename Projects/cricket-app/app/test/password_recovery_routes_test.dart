import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';
import 'package:pitch_app/src/core/auth/password_recovery.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/core/routing/routes.dart';

/// Code review, 2026-08-05: the password-recovery redirect may never fire.
///
/// `onboardingRedirect(..., recovering: true)` is correct and already unit
/// tested ("while a recovery is pending, the router insists on the reset
/// screen"). That tests the DECISION. Nothing tested the NOTIFICATION - and
/// go_router only re-evaluates `redirect` when its `refreshListenable` fires.
///
/// RouterRefresh listens to `authGateProvider` alone. The redirect also reads
/// `passwordRecoveryProvider`, which is a completely separate NotifierProvider.
/// So the flag can flip true with the gate unchanged - a user who is already
/// signed in on the device follows a reset link - and go_router is never told.
/// The user stays on Discover: exactly the bug the recovery work was for.
///
/// This is the same shape as the badge finding earlier in the day: a decision
/// nothing subscribes to is not a decision. Testing the pure function proves
/// only that the right answer EXISTS, never that anyone asks the question.
void main() {
  testWidgets('flipping into recovery navigates to the reset screen even when '
      'the auth gate does not change', (tester) async {
    final container = ProviderContainer(overrides: [
      // The gate stays FIXED for the whole test. That is the point: if the
      // redirect only re-runs because the gate moved, this test is the case it
      // misses, and it is the common one - somebody already signed in who taps
      // a reset link.
      authGateProvider.overrideWithValue(AuthGate.ready),
      // Discover is what /discover actually mounts; stub what it reads so the
      // test measures ROUTING, not whether a screen can render without a
      // backend.
      currentSessionProvider.overrideWithValue(null),
      isAnonymousProvider.overrideWithValue(false),
      dmInboxProvider.overrideWith((ref) async => const <Map<String, dynamic>>[]),
      notificationsProvider.overrideWith((ref) async => const <Map<String, dynamic>>[]),
      discoverFeedProvider.overrideWith((ref, q) async => const <Map<String, dynamic>>[]),
      homeLocationProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, isNot(Routes.resetPassword),
        reason: 'sanity: not on the reset screen before the recovery event');

    // The recovery event arrives. This is precisely what
    // passwordRecoveryListenerProvider does when Supabase delivers
    // AuthChangeEvent.passwordRecovery.
    container.read(passwordRecoveryProvider.notifier).begin();
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, Routes.resetPassword,
        reason: 'the redirect reads passwordRecoveryProvider but RouterRefresh '
            'listened only to authGateProvider, so go_router was never asked to '
            're-evaluate. The reset link landed the user on Discover with a '
            'half-finished recovery session that expires while they wonder what '
            'happened');
  });

  testWidgets('and completing the reset lets the router leave again',
      (tester) async {
    final container = ProviderContainer(overrides: [
      authGateProvider.overrideWithValue(AuthGate.ready),
      // Discover is what /discover actually mounts; stub what it reads so the
      // test measures ROUTING, not whether a screen can render without a
      // backend.
      currentSessionProvider.overrideWithValue(null),
      isAnonymousProvider.overrideWithValue(false),
      dmInboxProvider.overrideWith((ref) async => const <Map<String, dynamic>>[]),
      notificationsProvider.overrideWith((ref) async => const <Map<String, dynamic>>[]),
      discoverFeedProvider.overrideWith((ref, q) async => const <Map<String, dynamic>>[]),
      homeLocationProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);

    final router = container.read(goRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    container.read(passwordRecoveryProvider.notifier).begin();
    await tester.pumpAndSettle();
    expect(router.state.matchedLocation, Routes.resetPassword,
        reason: 'sanity: in recovery');

    // done() is what reset_password_screen calls after updateUser succeeds -
    // and the SCREEN then navigates itself (`context.go(Routes.discover)`).
    // The router is not supposed to move on its own here; what matters is that
    // the guard RELEASES, so the navigation the screen makes is not bounced
    // straight back to /reset-password by the redirect.
    container.read(passwordRecoveryProvider.notifier).done();
    await tester.pumpAndSettle();
    router.go(Routes.discover);
    await tester.pumpAndSettle();

    expect(router.state.matchedLocation, Routes.discover,
        reason: 'with the recovery finished the guard must let go. If it did '
            'not, the user would set their password successfully and then be '
            'thrown back onto the reset screen forever');
  });
}
