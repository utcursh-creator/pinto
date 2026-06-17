import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitch_app/src/app.dart';
import 'package:pitch_app/src/core/auth/auth_gate.dart';
import 'package:pitch_app/src/core/auth/auth_providers.dart';
import 'package:pitch_app/src/features/discover/presentation/discover_screen.dart';
import 'package:pitch_app/src/features/onboarding/presentation/create_profile_screen.dart';

void main() {
  testWidgets('a real user with no profile is redirected to create-profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGateProvider.overrideWithValue(AuthGate.needsProfile),
          anonBootstrapProvider.overrideWith((ref) async {}),
        ],
        child: const PitchApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CreateProfileScreen), findsOneWidget);
    expect(find.byType(DiscoverScreen), findsNothing);
    expect(find.text('Display name'), findsOneWidget);
  });

  testWidgets('an anonymous user can reach the shell (viewing allowed)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authGateProvider.overrideWithValue(AuthGate.anonymous),
          anonBootstrapProvider.overrideWith((ref) async {}),
        ],
        child: const PitchApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverScreen), findsOneWidget);
  });
}
