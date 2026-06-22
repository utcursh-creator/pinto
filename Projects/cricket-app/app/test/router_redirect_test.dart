import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/core/routing/routes.dart';

void main() {
  group('onboardingRedirect', () {
    test('public /watch/ bypasses the gate in every state (deep-link safe)', () {
      for (final gate in AuthGate.values) {
        expect(onboardingRedirect(gate, '/watch/m1'), isNull,
            reason: 'watch link must resolve under $gate');
      }
    });

    test('loading holds everything else on splash', () {
      expect(onboardingRedirect(AuthGate.loading, Routes.discover), Routes.splash);
      expect(onboardingRedirect(AuthGate.loading, Routes.splash), isNull);
    });

    test('anonymous can browse the shell but is moved off splash', () {
      expect(onboardingRedirect(AuthGate.anonymous, Routes.splash), Routes.discover);
      expect(onboardingRedirect(AuthGate.anonymous, Routes.matches), isNull);
    });

    test('needsProfile is funnelled to create-profile', () {
      expect(onboardingRedirect(AuthGate.needsProfile, Routes.discover),
          Routes.createProfile);
      expect(onboardingRedirect(AuthGate.needsProfile, Routes.createProfile), isNull);
    });

    test('ready leaves the onboarding screens for the shell', () {
      expect(onboardingRedirect(AuthGate.ready, Routes.splash), Routes.discover);
      expect(onboardingRedirect(AuthGate.ready, Routes.signIn), Routes.discover);
      expect(onboardingRedirect(AuthGate.ready, Routes.matches), isNull);
    });
  });
}
