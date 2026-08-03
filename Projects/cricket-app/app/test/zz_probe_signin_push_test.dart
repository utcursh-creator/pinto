import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/routing/app_router.dart';
import 'package:pitch_app/src/core/routing/router_refresh.dart';
import 'package:pitch_app/src/core/routing/routes.dart';

class _GateN extends Notifier<AuthGate> {
  @override
  AuthGate build() => AuthGate.anonymous;
  void set(AuthGate g) => state = g;
}

final _gateSrc = NotifierProvider<_GateN, AuthGate>(_GateN.new);

class _Stub extends StatelessWidget {
  const _Stub(this.label);
  final String label;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(label)));
}

late ProviderContainer _container;
late GoRouter _router;

Future<void> _pump(WidgetTester tester, String start) async {
  _container = ProviderContainer(overrides: [
    authGateProvider.overrideWith((ref) => ref.watch(_gateSrc)),
  ]);
  addTearDown(_container.dispose);
  // keep the refresh notifier alive (riverpod 3 auto-disposes unlistened
  // providers, which would silently kill the refresh listenable)
  _container.listen(routerRefreshProvider, (_, _) {}, fireImmediately: true);
  _container.listen(authGateProvider, (_, _) {}, fireImmediately: true);
  final refresh = _container.read(routerRefreshProvider);
  _router = GoRouter(
    initialLocation: start,
    refreshListenable: refresh,
    redirect: (context, state) => onboardingRedirect(
      _container.read(authGateProvider),
      state.matchedLocation,
      next: state.uri.queryParameters['next'],
    ),
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const _Stub('SPLASH')),
      GoRoute(path: Routes.signIn, builder: (_, _) => const _Stub('SIGNIN')),
      GoRoute(
          path: Routes.createProfile,
          builder: (_, _) => const _Stub('CREATE_PROFILE')),
      GoRoute(path: Routes.discover, builder: (_, _) => const _Stub('DISCOVER')),
      GoRoute(
          path: '/invite/:token',
          builder: (_, s) => _Stub('INVITE:${s.pathParameters['token']}')),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
}

String _loc() =>
    _router.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('CONTROL 1: no push - /discover + gate -> needsProfile redirects',
      (tester) async {
    await _pump(tester, Routes.discover);
    expect(find.text('DISCOVER'), findsOneWidget);
    _container.read(_gateSrc.notifier).set(AuthGate.needsProfile);
    await tester.pumpAndSettle();
    debugPrint('CONTROL1 loc=${_loc()} '
        'create=${find.text('CREATE_PROFILE').evaluate().length} '
        'discover=${find.text('DISCOVER').evaluate().length}');
    expect(find.text('CREATE_PROFILE'), findsOneWidget,
        reason: 'harness sanity: the refresh listenable must re-run redirect');
  });

  testWidgets('CONTROL 2: no push - /splash + gate -> ready redirects',
      (tester) async {
    _container = ProviderContainer(overrides: [
      authGateProvider.overrideWith((ref) => ref.watch(_gateSrc)),
      _gateSrc.overrideWith(_GateN.new),
    ]);
    await _pump(tester, Routes.splash);
    // anonymous on splash -> discover already
    debugPrint('CONTROL2 initial loc=${_loc()}');
    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('CONTROL2 loc=${_loc()}');
  });

  testWidgets('A: push /sign-in from /discover, gate -> ready', (tester) async {
    await _pump(tester, Routes.discover);
    expect(find.text('DISCOVER'), findsOneWidget);

    _router.push(Routes.signIn);
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget, reason: 'push landed');
    debugPrint('AFTER PUSH loc=${_loc()}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('AFTER READY loc=${_loc()} '
        'signin=${find.text('SIGNIN').evaluate().length} '
        'discover=${find.text('DISCOVER').evaluate().length}');
  });

  testWidgets('B: push signInThenReturnTo from /invite, gate -> ready',
      (tester) async {
    await _pump(tester, '/invite/tok1');
    expect(find.text('INVITE:tok1'), findsOneWidget);

    _router.push(Routes.signInThenReturnTo('/invite/tok1'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget);
    debugPrint('B AFTER PUSH loc=${_loc()}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('B AFTER READY loc=${_loc()} '
        'signin=${find.text('SIGNIN').evaluate().length} '
        'invite=${find.text('INVITE:tok1').evaluate().length}');
  });

  testWidgets('C: push signInThenReturnTo from /invite, gate -> needsProfile',
      (tester) async {
    await _pump(tester, '/invite/tok1');
    _router.push(Routes.signInThenReturnTo('/invite/tok1'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget);

    _container.read(_gateSrc.notifier).set(AuthGate.needsProfile);
    await tester.pumpAndSettle();
    debugPrint('C AFTER needsProfile loc=${_loc()} '
        'signin=${find.text('SIGNIN').evaluate().length} '
        'create=${find.text('CREATE_PROFILE').evaluate().length}');
  });

  testWidgets('D: push /sign-in from /discover, gate -> needsProfile',
      (tester) async {
    await _pump(tester, Routes.discover);
    _router.push(Routes.signIn);
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget);

    _container.read(_gateSrc.notifier).set(AuthGate.needsProfile);
    await tester.pumpAndSettle();
    debugPrint('D AFTER needsProfile loc=${_loc()} '
        'signin=${find.text('SIGNIN').evaluate().length} '
        'create=${find.text('CREATE_PROFILE').evaluate().length}');
  });

  // The REAL gate sequence: authGateProvider only watches myProfileProvider
  // once the session is non-anonymous, so the first watch is a fresh
  // AsyncLoading -> the gate passes through `loading` (or `needsProfile` when a
  // stale null is cached) BEFORE it reaches `ready`.
  testWidgets('F: /discover + push sign-in, anonymous -> loading -> ready',
      (tester) async {
    await _pump(tester, Routes.discover);
    _router.push(Routes.signIn);
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget);

    _container.read(_gateSrc.notifier).set(AuthGate.loading);
    await tester.pumpAndSettle();
    debugPrint('F mid loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'splash=${find.text('SPLASH').evaluate().length}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('F end loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'discover=${find.text('DISCOVER').evaluate().length}');
  });

  testWidgets('G: /discover + push sign-in, anonymous -> needsProfile -> ready',
      (tester) async {
    await _pump(tester, Routes.discover);
    _router.push(Routes.signIn);
    await tester.pumpAndSettle();

    _container.read(_gateSrc.notifier).set(AuthGate.needsProfile);
    await tester.pumpAndSettle();
    debugPrint('G mid loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'create=${find.text('CREATE_PROFILE').evaluate().length}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('G end loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'discover=${find.text('DISCOVER').evaluate().length}');
  });

  testWidgets('H: /invite + push sign-in?next, anonymous -> loading -> ready',
      (tester) async {
    await _pump(tester, '/invite/tok1');
    _router.push(Routes.signInThenReturnTo('/invite/tok1'));
    await tester.pumpAndSettle();
    expect(find.text('SIGNIN'), findsOneWidget);

    _container.read(_gateSrc.notifier).set(AuthGate.loading);
    await tester.pumpAndSettle();
    debugPrint('H mid loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'splash=${find.text('SPLASH').evaluate().length}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('H end loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'invite=${find.text('INVITE:tok1').evaluate().length}');
  });

  testWidgets('I: /invite + push sign-in?next, anon -> needsProfile -> ready',
      (tester) async {
    await _pump(tester, '/invite/tok1');
    _router.push(Routes.signInThenReturnTo('/invite/tok1'));
    await tester.pumpAndSettle();

    _container.read(_gateSrc.notifier).set(AuthGate.needsProfile);
    await tester.pumpAndSettle();
    debugPrint('I mid loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'create=${find.text('CREATE_PROFILE').evaluate().length}');

    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    debugPrint('I end loc=${_loc()} signin=${find.text('SIGNIN').evaluate().length} '
        'invite=${find.text('INVITE:tok1').evaluate().length}');
  });

  testWidgets('E: can the user get back? pop from the stuck sign-in',
      (tester) async {
    await _pump(tester, Routes.discover);
    _router.push(Routes.signIn);
    await tester.pumpAndSettle();
    _container.read(_gateSrc.notifier).set(AuthGate.ready);
    await tester.pumpAndSettle();
    final canPop = _router.canPop();
    debugPrint('E canPop=$canPop backButton='
        '${find.byType(BackButton).evaluate().length}');
  });
}
