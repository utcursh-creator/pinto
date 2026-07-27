import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';

/// The anchor now DERIVES from the saved home base instead of being pushed into
/// it by DiscoverScreen.build. That push (ref.listen + notifier mutation) flushed
/// homeLocationProvider during build and tripped
/// "setState() called during build" every time a signed-in user opened Discover -
/// found by driving the app on the simulator, fix run 2026-07-07.
void main() {
  test('falls back to the city centre when no home base is saved', () {
    final c = ProviderContainer(overrides: [
      homeLocationProvider.overrideWith((_) async => null),
    ]);
    addTearDown(c.dispose);
    expect(c.read(anchorProvider).lat, 19.07);
  });

  test('adopts the saved home base once it resolves', () async {
    final c = ProviderContainer(overrides: [
      homeLocationProvider
          .overrideWith((_) async => (lat: 12.34, lng: 56.78, label: 'Home')),
    ]);
    addTearDown(c.dispose);
    // before the future resolves the fallback stands
    expect(c.read(anchorProvider).lat, 19.07);
    await c.read(homeLocationProvider.future);
    expect(c.read(anchorProvider).lat, 12.34);
    expect(c.read(anchorProvider).lng, 56.78);
  });

  test('a user-chosen anchor survives the home base resolving', () async {
    final c = ProviderContainer(overrides: [
      homeLocationProvider
          .overrideWith((_) async => (lat: 9.0, lng: 9.0, label: 'Home')),
    ]);
    addTearDown(c.dispose);
    c.read(anchorProvider.notifier).set((lat: 1, lng: 2, radiusM: 5000));
    await c.read(homeLocationProvider.future);
    expect(c.read(anchorProvider).lat, 1, reason: 'the user picked this');
    expect(c.read(anchorProvider).lng, 2);
    expect(c.read(anchorProvider).radiusM, 5000);
  });
}
