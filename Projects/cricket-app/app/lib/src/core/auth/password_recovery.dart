import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
import 'auth_providers.dart';

/// Whether the app is holding a RECOVERY session - i.e. the user followed the
/// link in a password-reset email and is signed in only long enough to choose a
/// new password (review #2, finding 8).
///
/// Nothing listened for this event before, so even a correct link handed the
/// app a session and then did nothing with it: the user landed on Discover,
/// still not knowing their password, with a session that expires.
class PasswordRecoveryNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void begin() => state = true;
  void done() => state = false;
}

final passwordRecoveryProvider =
    NotifierProvider<PasswordRecoveryNotifier, bool>(
        PasswordRecoveryNotifier.new);

/// Watches the auth stream for the recovery event. Kept separate from
/// anonBootstrapProvider so the two listeners cannot mask each other.
final passwordRecoveryListenerProvider = Provider<void>((ref) {
  ref.listen(authStateChangesProvider, (_, next) {
    if (next.value?.event == AuthChangeEvent.passwordRecovery) {
      ref.read(passwordRecoveryProvider.notifier).begin();
    }
  });
});

/// The one write the reset screen makes, behind a provider so a widget test can
/// supply a fake instead of a real GoTrue call.
typedef PasswordUpdater = Future<void> Function(String password);

final passwordUpdaterProvider = Provider<PasswordUpdater>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (password) async {
    await client.auth.updateUser(UserAttributes(password: password));
  };
});
