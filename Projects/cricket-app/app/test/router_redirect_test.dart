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

    // An invite or tournament-join link asks an anonymous visitor to sign in.
    // Signing in flips the gate to ready, and the ready branch then sent every
    // onboarding location to /discover - so the link the user was accepting was
    // thrown away at the exact moment they qualified to accept it, with no way
    // back to it. `next` carries the destination through the sign-in.
    group('a link survives the sign-in it required', () {
      test('ready returns to the link instead of the shell', () {
        expect(
          onboardingRedirect(AuthGate.ready, Routes.signIn,
              next: '/invite/tok123'),
          '/invite/tok123',
        );
        expect(
          onboardingRedirect(AuthGate.ready, Routes.signIn,
              next: '/join-tournament/tok9'),
          '/join-tournament/tok9',
        );
      });

      test('a user with no profile keeps the link across create-profile', () {
        // sent to create-profile, but the link is carried along
        expect(
          onboardingRedirect(AuthGate.needsProfile, Routes.discover,
              next: '/invite/tok123'),
          '${Routes.createProfile}?next=%2Finvite%2Ftok123',
        );
        // and once the profile exists, it resolves
        expect(
          onboardingRedirect(AuthGate.ready, Routes.createProfile,
              next: '/invite/tok123'),
          '/invite/tok123',
        );
      });

      test('an off-app or malformed next is ignored', () {
        for (final bad in [
          'https://evil.example/x',
          '//evil.example/x',
          'invite/tok',
          '',
        ]) {
          expect(
            onboardingRedirect(AuthGate.ready, Routes.signIn, next: bad),
            Routes.discover,
            reason: '"$bad" must not be followed',
          );
        }
      });

      test('next changes nothing for an ordinary in-app location', () {
        expect(
          onboardingRedirect(AuthGate.ready, Routes.matches,
              next: '/invite/tok123'),
          isNull,
        );
      });
    });
  });
}
