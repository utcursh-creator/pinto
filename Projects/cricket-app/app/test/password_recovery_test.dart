import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/password_recovery.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/core/routing/routes.dart';
import 'package:pitch_app/src/features/auth/presentation/reset_password_screen.dart';

/// Whole-system review #2 (2026-07-28), finding 8 (HIGH): "Reset password"
/// emails a link that can never re-enter the app.
///
/// Three independent breaks in one chain, each verified in the review:
///   1. resetPasswordForEmail was called with no `redirectTo`, so GoTrue built
///      the link against the project's Site URL - 127.0.0.1:3000 - and the
///      phone's browser showed a connection error.
///   2. nothing listened for AuthChangeEvent.passwordRecovery, so even a
///      correct link that handed a recovery session to the app did nothing.
///   3. no screen anywhere called updateUser(password:), so there was nowhere
///      for that session to be spent.
///
/// A locked-out user had no path back in at all - by link or by code - unlike
/// team invites and tournament joins, which both have a manual code fallback.
void main() {
  test('the reset email points back at the app, not at Site URL', () {
    final src = File(
            'lib/src/features/profile/presentation/settings_screen.dart')
        .readAsStringSync();
    final at = src.indexOf('resetPasswordForEmail');
    expect(at, isNot(-1), reason: 'sanity: the reset call still exists');
    final call = src.substring(at, src.indexOf(';', at));
    expect(call, contains('redirectTo'),
        reason: 'without redirectTo, GoTrue builds the recovery link against '
            'the project Site URL (127.0.0.1:3000 locally), and the link opens '
            'a connection error on the phone:\n$call');
    expect(call, contains('io.supabase.pitch://'),
        reason: 'and it has to be the scheme this app already registers on '
            'both platforms for the OAuth callback - a domain we do not own an '
            'App Link for cannot hand off to the app');
  });

  test('a recovery session is caught and routed', () {
    final src =
        File('lib/src/core/auth/password_recovery.dart').readAsStringSync();
    expect(src, contains('AuthChangeEvent.passwordRecovery'),
        reason: 'the recovery session arrives as an auth event; nothing was '
            'listening for it');
  });

  test('while a recovery is pending, the router insists on the reset screen',
      () {
    expect(
      onboardingRedirect(AuthGate.ready, Routes.discover, recovering: true),
      Routes.resetPassword,
      reason: 'a user who followed a reset link is signed in with a RECOVERY '
          'session - dropping them on Discover leaves them still not knowing '
          'their password, with a session that expires',
    );
    expect(
      onboardingRedirect(AuthGate.ready, Routes.resetPassword,
          recovering: true),
      isNull,
      reason: 'and the reset screen itself must not redirect to itself',
    );
    expect(
      onboardingRedirect(AuthGate.ready, Routes.discover),
      isNull,
      reason: 'CONTROL: with no recovery pending nothing changes - this '
          'redirect runs on every navigation in the app',
    );
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('the reset screen sets a new password on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        String? saved;
        final container = ProviderContainer(overrides: [
          passwordUpdaterProvider.overrideWithValue((p) async => saved = p),
        ]);
        addTearDown(container.dispose);
        container.read(passwordRecoveryProvider.notifier).begin();

        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ResetPasswordScreen()),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.widgetWithText(TextField, 'New password'), 'newpassword1');
        await tester.enterText(
            find.widgetWithText(TextField, 'Repeat it'), 'newpassword1');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Set password'));
        await tester.pumpAndSettle();

        expect(saved, 'newpassword1');
        expect(container.read(passwordRecoveryProvider), isFalse,
            reason: 'and the recovery is over, so the router stops pinning the '
                'user to this screen');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CONTROL: it refuses a mismatch and a short password on '
        '$platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        String? saved;
        final container = ProviderContainer(overrides: [
          passwordUpdaterProvider.overrideWithValue((p) async => saved = p),
        ]);
        addTearDown(container.dispose);
        container.read(passwordRecoveryProvider.notifier).begin();

        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ResetPasswordScreen()),
        ));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.widgetWithText(TextField, 'New password'), 'newpassword1');
        await tester.enterText(
            find.widgetWithText(TextField, 'Repeat it'), 'newpassword2');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Set password'));
        await tester.pumpAndSettle();
        expect(saved, isNull, reason: 'two different passwords is a typo, and '
            'the user cannot check it afterwards - they are locked out either '
            'way');
        expect(find.textContaining('do not match'), findsOneWidget);

        await tester.enterText(
            find.widgetWithText(TextField, 'New password'), 'short');
        await tester.enterText(
            find.widgetWithText(TextField, 'Repeat it'), 'short');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Set password'));
        await tester.pumpAndSettle();
        expect(saved, isNull,
            reason: 'GoTrue rejects under 6 characters server-side; say so '
                'before spending the recovery session on it');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
