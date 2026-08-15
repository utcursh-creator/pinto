import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_gate.dart';
import '../auth/password_recovery.dart';

/// Bumps go_router's `refreshListenable` whenever anything the redirect READS
/// changes, so the redirect is re-evaluated.
///
/// THE RULE: every provider `onboardingRedirect` is given must be listened to
/// here. go_router calls `redirect` only when this listenable fires, so a
/// provider that is read but not listened to is a decision nobody ever asks
/// for. That is not hypothetical - `passwordRecoveryProvider` was exactly this:
/// the redirect read it, only authGateProvider was listened to, and a user who
/// was already signed in and followed a reset link stayed on Discover while
/// their half-finished recovery session quietly expired. The pure function was
/// correct and unit-tested the whole time.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(authGateProvider, (_, _) => notifyListeners());
    ref.listen(passwordRecoveryProvider, (_, _) => notifyListeners());
  }
}

final routerRefreshProvider = Provider<RouterRefresh>((ref) {
  final refresh = RouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return refresh;
});
