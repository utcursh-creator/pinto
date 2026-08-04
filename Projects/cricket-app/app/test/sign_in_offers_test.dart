import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/config/env.dart';
import 'package:pitch_app/src/features/auth/presentation/sign_in_screen.dart';

/// CRITICAL-adjacent (whole-system review #2): the sign-in screen offered
/// "Continue with Google" unconditionally. On iOS without GOOGLE_IOS_CLIENT_ID -
/// and its reversed-client-id URL scheme in Info.plist - that opens a flow that
/// can never come back, and the user concludes their account is broken.
///
/// SupabaseEnv.googleConfigured had existed since the OAuth wiring and nothing
/// consulted it. These tests make the offer follow the configuration.
void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Google is offered only when it is configured on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: SignInScreen()),
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Continue with Google'),
          SupabaseEnv.googleConfigured ? findsOneWidget : findsNothing,
          reason: 'the button must appear exactly when the client IDs this '
              'platform needs are present - offering a sign-in the app cannot '
              'complete is worse than not offering it',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test('googleConfigured demands the iOS client id on iOS', () {
    // Pins the RULE, independent of how this particular build was defined:
    // Android needs only the web client (its OAuth client is matched by package
    // + SHA), iOS additionally needs its own client id.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final androidNeedsOnlyWeb =
        SupabaseEnv.googleWebClientId.isEmpty || SupabaseEnv.googleConfigured;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final iosAlsoNeedsIos = SupabaseEnv.googleIosClientId.isNotEmpty
        ? SupabaseEnv.googleConfigured
        : !SupabaseEnv.googleConfigured;
    debugDefaultTargetPlatformOverride = null;

    expect(androidNeedsOnlyWeb, isTrue);
    expect(iosAlsoNeedsIos, isTrue,
        reason: 'on iOS, a missing GOOGLE_IOS_CLIENT_ID must make '
            'googleConfigured false');
  });
}
