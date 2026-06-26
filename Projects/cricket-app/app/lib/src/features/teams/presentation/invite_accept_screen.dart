import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';

/// Opens from an invite link (`/invite/:token`). A signed-in user can redeem it
/// to join the team; an anonymous visitor is asked to sign in first.
class InviteAcceptScreen extends ConsumerStatefulWidget {
  const InviteAcceptScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(identityRepositoryProvider).acceptInvite(widget.token);
      ref.invalidate(myTeamsProvider);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('You joined the team')));
      context.go(Routes.myTeams);
    } catch (e) {
      setState(() => _message = 'Could not join: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    return AdaptiveScaffold(
      title: 'Team invite',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                isAnon
                    ? 'You have been invited to join a team on Pitch. Sign in to accept.'
                    : 'You have been invited to join a team. Accept to become a member.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isAnon)
                FilledButton(
                  onPressed: () => context.push(Routes.signIn),
                  child: const Text('Sign in to join'),
                )
              else
                FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                        )
                      : const Text('Join team'),
                ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
