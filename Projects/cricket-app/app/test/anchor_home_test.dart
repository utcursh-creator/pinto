import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';

/// The discover anchor crashed the build phase TWICE while being fixed, so these
/// lock the shape that finally holds (see discover_providers.dart):
///   - anchorProvider holds ONLY the user's explicit choice and has NO
///     ASYNC dependency (its only dependency is the sync signed-in user id, so
///     that a chosen city does not outlive its owner - finding 55), so it can
///     never invalidate itself.
///   - the anchor actually used is derived by the pure effectiveAnchor().
/// The rule: no provider may watch homeLocationProvider. Widgets may.
void main() {
  group('anchorProvider holds only an explicit choice', () {
    test('starts null - nothing chosen', () {
      final c = ProviderContainer(overrides: [
        // anchorProvider now watches WHO is signed in, so that one person's
        // chosen city does not follow the next person signed in on this phone
        // (review #2, finding 55). Nothing here needs a real session.
        currentSessionProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      expect(c.read(anchorProvider), isNull);
    });

    test('has no async dependency, so resolving a home base cannot disturb it',
        () {
      final c = ProviderContainer(overrides: [
        currentSessionProvider.overrideWithValue(null),
        homeLocationProvider
            .overrideWith((_) async => (lat: 9.0, lng: 9.0, label: 'Home')),
      ]);
      addTearDown(c.dispose);
      c.read(anchorProvider.notifier).set((lat: 1, lng: 2, radiusM: 5000));
      expect(c.read(anchorProvider), (lat: 1.0, lng: 2.0, radiusM: 5000.0));
    });

    test('clear() returns to deriving from the home base', () {
      final c = ProviderContainer(overrides: [
        // anchorProvider now watches WHO is signed in, so that one person's
        // chosen city does not follow the next person signed in on this phone
        // (review #2, finding 55). Nothing here needs a real session.
        currentSessionProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      c.read(anchorProvider.notifier).set((lat: 1, lng: 2, radiusM: 5000));
      c.read(anchorProvider.notifier).clear();
      expect(c.read(anchorProvider), isNull);
    });
  });

  group('effectiveAnchor', () {
    test('falls back to the city centre with no choice and no home base', () {
      expect(effectiveAnchor(null, null), kFallbackAnchor);
    });

    test('uses the saved home base when the user has not chosen', () {
      final a = effectiveAnchor(null, (lat: 12.34, lng: 56.78, label: 'Home'));
      expect(a.lat, 12.34);
      expect(a.lng, 56.78);
      expect(a.radiusM, kFallbackAnchor.radiusM);
    });

    test("the user's choice beats the home base", () {
      final a = effectiveAnchor(
          (lat: 1, lng: 2, radiusM: 5000), (lat: 9, lng: 9, label: 'Home'));
      expect(a.lat, 1);
      expect(a.lng, 2);
      expect(a.radiusM, 5000, reason: 'their radius is kept too');
    });
  });
}
