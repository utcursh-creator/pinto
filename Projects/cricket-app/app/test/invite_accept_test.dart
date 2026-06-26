import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/features/teams/presentation/invite_accept_screen.dart';

Future<void> _pump(WidgetTester tester, {required bool anon}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [isAnonymousProvider.overrideWithValue(anon)],
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
        expect(find.widgetWithText(FilledButton, 'Join team'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('signed-in visitor can join on $platform', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await _pump(tester, anon: false);
        expect(tester.takeException(), isNull);
        expect(find.widgetWithText(FilledButton, 'Join team'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
