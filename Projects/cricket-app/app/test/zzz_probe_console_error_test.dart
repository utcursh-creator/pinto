// TEMPORARY PROBE - delete after running.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/features/scoring/data/match_providers.dart';
import 'package:pitch_app/src/features/scoring/data/match_repository.dart';
import 'package:pitch_app/src/features/scoring/presentation/scoring_console_screen.dart';

class _FakeMatchRepository extends Fake implements MatchRepository {}

void main() {
  test('PROBE riverpod 3.3.2: does a failing FutureProvider retry?', () async {
    var calls = 0;
    final p = FutureProvider<int>((ref) async {
      calls++;
      throw Exception('offline');
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sub = c.listen(p, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(Duration.zero);
    // ignore: avoid_print
    print('PROBE first failure: state=${sub.read()} '
        'isLoading=${sub.read().isLoading} hasError=${sub.read().hasError} calls=$calls');
    await Future<void>.delayed(const Duration(milliseconds: 700));
    // ignore: avoid_print
    print('PROBE after 700ms: state=${sub.read()} '
        'isLoading=${sub.read().isLoading} calls=$calls');
  });

  test('PROBE: an Error (not Exception) is not retried', () async {
    var calls = 0;
    final p = FutureProvider<int>((ref) async {
      calls++;
      throw StateError('boom');
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final sub = c.listen(p, (_, _) {}, fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // ignore: avoid_print
    print('PROBE Error case: state=${sub.read()} '
        'isLoading=${sub.read().isLoading} calls=$calls');
  });

  testWidgets('PROBE console renders on load failure', (tester) async {
    var matchCalls = 0;
    var inningsCalls = 0;
    final container = ProviderContainer(
      overrides: [
        matchRepositoryProvider.overrideWithValue(_FakeMatchRepository()),
        matchProvider.overrideWith((ref, id) async {
          matchCalls++;
          throw Exception('SocketException: connection failed');
        }),
        currentInningsProvider.overrideWith((ref, id) async {
          inningsCalls++;
          throw Exception('SocketException: connection failed');
        }),
        matchSquadProvider.overrideWith((ref, id) async {
          throw Exception('SocketException: connection failed');
        }),
        matchTeamNamesProvider.overrideWith((ref, id) async {
          throw Exception('SocketException: connection failed');
        }),
      ],
    );
    addTearDown(container.dispose);

    Widget app({required bool showConsole}) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: showConsole
                ? const ScoringConsoleScreen(matchId: 'm1')
                : const Scaffold(body: Text('ELSEWHERE')),
          ),
        );

    String snap() {
      final spinner =
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
              find.byType(CupertinoActivityIndicatorStub).evaluate().isNotEmpty;
      final msg = find.textContaining('No innings yet').evaluate().length;
      return 'spinner=$spinner msg=$msg matchCalls=$matchCalls '
          'inningsCalls=$inningsCalls '
          'matchState=${container.read(matchProvider('m1'))} ';
    }

    await tester.pumpWidget(app(showConsole: true));
    await tester.pump();
    // ignore: avoid_print
    print('PROBE t=0   ${snap()}');
    await tester.pump(const Duration(seconds: 2));
    // ignore: avoid_print
    print('PROBE t=2s  ${snap()}');
    await tester.pump(const Duration(seconds: 60));
    await tester.pump();
    // ignore: avoid_print
    print('PROBE t=62s ${snap()}');

    // leave the console, then come back - does anything re-fetch?
    await tester.pumpWidget(app(showConsole: false));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(app(showConsole: true));
    await tester.pump(const Duration(seconds: 5));
    // ignore: avoid_print
    print('PROBE re-entry ${snap()}');
    expect(tester.takeException(), isNull);
  });
}

/// Stand-in so `snap()` compiles without importing cupertino directly.
class CupertinoActivityIndicatorStub extends StatelessWidget {
  const CupertinoActivityIndicatorStub({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
