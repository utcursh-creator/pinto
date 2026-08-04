import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../../core/supabase/supabase_providers.dart';
import '../../../core/ui/human_error.dart';
import '../../identity/data/identity_repository.dart';

/// PROF-2 / MISS-4: account management + store-compliance surface - password
/// reset, email change, ACCOUNT DELETION (Apple/Google reject apps without it),
/// privacy/terms pointers, and about/version.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _resetPassword() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final email = ref.read(currentSessionProvider)?.user.email;
    if (email == null || email.isEmpty) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('No email on this account (signed in with Google?).')));
      return;
    }
    try {
      // redirectTo, or GoTrue builds the link against the project Site URL -
      // 127.0.0.1:3000 - and the phone's browser shows a connection error
      // (review #2, finding 8). This is the scheme the app already registers on
      // both platforms for the OAuth callback.
      await ref.read(supabaseClientProvider).auth.resetPasswordForEmail(
            email,
            redirectTo: 'io.supabase.pitch://login-callback',
          );
      messenger?.showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e, fallback: 'Could not send.'))));
    }
  }

  Future<void> _changeEmail() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ctrl = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change email'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'New email'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Update')),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    try {
      await ref
          .read(supabaseClientProvider)
          .auth
          .updateUser(UserAttributes(email: email));
      messenger?.showSnackBar(SnackBar(
          content: Text('Confirmation sent to $email - open it to finish.')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e, fallback: 'Could not update.'))));
    }
  }

  /// MISS-4: the store-blocker. Deletes (or anonymizes, when match history
  /// must survive) the account via the delete_my_account RPC, then signs out.
  Future<void> _deleteAccount() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This permanently removes your profile, posts, photos and '
            'messages. '
            'Completed matches stay in your opponents\' history under '
            '"Deleted user". This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final c = ref.read(supabaseClientProvider);
      // Photos FIRST, and deliberately not swallowed. The RPC revokes this
      // user's auth rows, after which the Storage API can no longer act as
      // them and their pictures are stranded in a public bucket forever. If
      // this throws, the account is NOT deleted and the user can try again -
      // far better than a deletion that half happened (review #2, finding 52).
      await ref.read(identityRepositoryProvider).deleteMyUploads();
      await c.rpc('delete_my_account');
      await c.auth.signOut();
      // the auth listener re-anons + the router gate takes over
      if (mounted) context.go(Routes.discover);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e, fallback: 'Could not delete.'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(currentSessionProvider)?.user.email;
    return AdaptiveScaffold(
      title: 'Settings',
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Account', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          if (email != null && email.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: const Text('Email'),
              subtitle: Text(email),
            ),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Reset password'),
            subtitle: const Text('We email you a reset link'),
            onTap: _busy ? null : _resetPassword,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Change email'),
            onTap: _busy ? null : _changeEmail,
          ),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Legal', style: TextStyle(fontWeight: FontWeight.w500)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('pitch.app/privacy'),
            // MISS-4: store review requires a working link, not dead text
            onTap: () => launchUrl(Uri.parse('https://pitch.app/privacy'),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of service'),
            subtitle: const Text('pitch.app/terms'),
            onTap: () => launchUrl(Uri.parse('https://pitch.app/terms'),
                mode: LaunchMode.externalApplication),
          ),
          const Divider(height: 24),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Pitch v1.0.0 - find, play and score cricket'),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.all(20),
            child: OutlinedButton(
              onPressed: _busy ? null : _deleteAccount,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : const Text('Delete account'),
            ),
          ),
        ],
      ),
    );
  }
}
