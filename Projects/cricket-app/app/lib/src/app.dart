import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_providers.dart';
import 'core/auth/password_recovery.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

/// One MaterialApp for both platforms (Cupertino widgets harmonize inside it).
/// The theme is platform-tuned; the per-screen chrome adapts in AdaptiveScaffold
/// and the shell. defaultTargetPlatform is overridable in tests.
class PitchApp extends ConsumerWidget {
  const PitchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kick off the anonymous-session bootstrap for login-free viewing.
    ref.watch(anonBootstrapProvider);
    // And listen for a password-reset link handing us a recovery session -
    // without a watcher this listener never runs, and the reset flow is only as
    // alive as the thing watching it (review #2, finding 8).
    ref.watch(passwordRecoveryListenerProvider);

    final router = ref.watch(goRouterProvider);
    final useCupertino = defaultTargetPlatform == TargetPlatform.iOS;

    return MaterialApp.router(
      title: 'Pitch',
      debugShowCheckedModeBanner: false,
      theme: useCupertino ? AppTheme.cupertino() : AppTheme.material(),
      routerConfig: router,
    );
  }
}
