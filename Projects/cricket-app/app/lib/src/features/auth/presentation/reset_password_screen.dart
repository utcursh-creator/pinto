import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/password_recovery.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../../core/ui/human_error.dart';

/// Where a password-reset link lands (review #2, finding 8).
///
/// The user arrives holding a RECOVERY session: signed in, but only long enough
/// to choose a new password. Until this screen existed there was nowhere for
/// that session to be spent - no route, no updateUser call - so a locked-out
/// user had no way back into their account at all.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final a = _first.text;
    final b = _second.text;
    // Checked HERE, before the recovery session is spent: a link can only be
    // used once, so a server-side rejection costs the user another email.
    if (a.length < 6) {
      setState(() => _error = 'Use at least 6 characters.');
      return;
    }
    if (a != b) {
      setState(() => _error = 'Those two do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordUpdaterProvider)(a);
      ref.read(passwordRecoveryProvider.notifier).done();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Password updated. You are signed in.')));
      context.go(Routes.discover);
    } catch (e) {
      setState(() =>
          _error = humanError(e, fallback: 'Could not set that password.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      title: 'Set a new password',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'You followed a reset link, so you are signed in for the moment. '
            'Choose a new password to keep it that way.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _first,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _second,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repeat it'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Set password'),
          ),
        ],
      ),
    );
  }
}
