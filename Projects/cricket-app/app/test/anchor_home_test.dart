import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/discover/data/discover_providers.dart';

void main() {
  test('default anchor is the city centre until a home base is adopted', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(anchorProvider).lat, 19.07);
  });

  test('adoptHome applies the saved home base when the user has not chosen', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(anchorProvider.notifier).adoptHome(12.34, 56.78);
    expect(c.read(anchorProvider).lat, 12.34);
    expect(c.read(anchorProvider).lng, 56.78);
  });

  test('a user-chosen anchor is not overridden by adoptHome', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(anchorProvider.notifier).set((lat: 1, lng: 2, radiusM: 5000));
    c.read(anchorProvider.notifier).adoptHome(9, 9);
    expect(c.read(anchorProvider).lat, 1);
    expect(c.read(anchorProvider).lng, 2);
  });
}
