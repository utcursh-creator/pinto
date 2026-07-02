import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/features/identity/data/identity_providers.dart';
import 'package:pitch_app/src/features/teams/presentation/invite_accept_screen.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool anon,
  ({String teamName, bool redeemable})? preview = (
    teamName: 'Strikers',
    redeemable: true,
  ),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isAnonymousProvider.overrideWithValue(anon),
        invitePreviewProvider.overrideWith((ref, token) async => preview),
      ],
      child: const MaterialApp(home: InviteAcceptScreen(token: 'tok123')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('an invite link bypasses the onboarding gate', () {
    expect(onboardingRedirect(AuthGate.anonymous, '/invite/tok123'), isNull);
    expect(onboardingRedirect(AuthGate.needsProfile, '/invite/tok123'), isNull);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('anonymous visitor is asked to sign in on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, anon: true);
        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Sign in to join'), findsOneWidget);
        // DISC-8: the pre-flight names the inviting team
        expect(find.textContaining('Strikers'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('signed-in visitor can join the NAMED team on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, anon: false);
        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Join Strikers'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('an unknown token shows a clear invalid state on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, anon: false, preview: null);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('not valid'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a used token shows an already-used state on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester,
            anon: false, preview: (teamName: 'Strikers', redeemable: false));
        expect(tester.takeException(), isNull);
        expect(find.textContaining('already been used'), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
