import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Probe: does a sync Provider that does asyncValue.when(...) see `loading`
// when the async provider rebuilds because a WATCHED dependency changed?
final depProvider = StateProvider<int>((ref) => 0);

final asyncProvider = FutureProvider<String>((ref) async {
  final n = ref.watch(depProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return 'value-$n';
});

final gateProvider = Provider<String>((ref) {
  final v = ref.watch(asyncProvider);
  return v.when(
    data: (d) => 'ready:$d',
    loading: () => 'LOADING',
    error: (_, _) => 'error',
  );
});

void main() {
  test('watch-triggered rebuild takes the loading branch of when()', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <String>[];
    container.listen<String>(gateProvider, (_, next) => seen.add(next),
        fireImmediately: true);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(container.read(gateProvider), 'ready:value-0');

    // Simulate the token refresh: the watched dependency emits a new value.
    container.read(depProvider.notifier).state = 1;

    // Flush the scheduler the way a frame would.
    await Future<void>.delayed(Duration.zero);
    final duringReload = container.read(gateProvider);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    // ignore: avoid_print
    print('SEEN: $seen');
    // ignore: avoid_print
    print('DURING RELOAD: $duringReload');
    expect(container.read(gateProvider), 'ready:value-1');
  });
}
