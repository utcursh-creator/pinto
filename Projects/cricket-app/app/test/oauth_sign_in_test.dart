import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/config/env.dart';
import 'package:pitch_app/src/features/auth/data/oauth_sign_in.dart';
import 'package:pitch_app/src/features/auth/presentation/sign_in_screen.dart';

class _FakeOAuth implements OAuthService {
  bool googleCalled = false;
  bool appleCalled = false;

  @override
  Future<void> nativeGoogleSignIn() async => googleCalled = true;

  @override
  Future<void> appleSignIn() async => appleCalled = true;
}

void main() {
  testWidgets('Google button wired on iOS + Apple shown only on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final fake = _FakeOAuth();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [oAuthServiceProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue with Apple'), findsOneWidget);

      // The Google button is now gated on SupabaseEnv.googleConfigured, because
      // an unconfigured build used to show a button that opened a flow it could
      // never finish. In a build WITHOUT the client ids (which is what `flutter
      // test` normally is) the correct behaviour is for it to be absent - so
      // assert whichever of the two is true, rather than pinning the old
      // unconditional behaviour.
      if (SupabaseEnv.googleConfigured) {
        expect(find.text('Continue with Google'), findsOneWidget);
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(fake.googleCalled, isTrue);
      } else {
        expect(find.text('Continue with Google'), findsNothing,
            reason: 'without client ids the app must not offer Google sign-in');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Apple button hidden on Android; Google still wired', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final fake = _FakeOAuth();
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [oAuthServiceProvider.overrideWithValue(fake)],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue with Apple'), findsNothing);

      // Same gating as the iOS case above: without client ids the app must not
      // offer a Google sign-in it cannot complete.
      if (SupabaseEnv.googleConfigured) {
        expect(find.text('Continue with Google'), findsOneWidget);
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        expect(fake.googleCalled, isTrue);
      } else {
        expect(find.text('Continue with Google'), findsNothing,
            reason: 'without client ids the app must not offer Google sign-in');
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
