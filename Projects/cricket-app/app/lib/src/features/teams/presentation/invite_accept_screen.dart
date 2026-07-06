import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_providers.dart';
import '../../identity/data/identity_repository.dart';

/// Opens from an invite link (`/invite/:token`). Pre-flights the token so the
/// visitor sees WHICH team invited them and a clear invalid/used state before
/// tapping Join (DISC-8). A signed-in user redeems it; an anonymous visitor is
/// asked to sign in first.
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
      // DISC-8: map the known failures to friendly lines, not raw errors.
      final raw = '$e';
      setState(() => _message = raw.contains('invite expired')
          ? 'This invite has expired - ask the captain for a fresh link.'
          : raw.contains('invite fully used')
              ? 'This invite has reached its member limit.'
              : raw.contains('not found or already used')
                  ? 'This invite has already been used or is no longer valid.'
                  : 'Could not join: $raw');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    final preview = ref.watch(invitePreviewProvider(widget.token));
    return AdaptiveScaffold(
      title: 'Team invite',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: preview.when(
            loading: () => const CircularProgressIndicator.adaptive(),
            // The preview is best-effort: on a load error fall back to the
            // pre-DISC-8 generic copy rather than blocking the join.
            error: (_, _) => _body(context, isAnon, teamName: null, valid: true),
            data: (p) => p == null
                ? _invalid(context,
                    'This invite link is not valid. Ask the captain to send a new one.')
                : !p.redeemable
                    // DISC-8: say WHY it is dead, not one generic line
                    ? _invalid(context, switch (p.reason) {
                        'expired' =>
                          'This invite to ${p.teamName} has expired - ask the '
                              'captain for a fresh link.',
                        'revoked' =>
                          'This invite to ${p.teamName} was revoked by the team.',
                        'used_up' =>
                          'This invite to ${p.teamName} has reached its member limit.',
                        _ =>
                          'This invite to ${p.teamName} has already been used.',
                      })
                    : _body(context, isAnon, teamName: p.teamName, valid: true),
          ),
        ),
      ),
    );
  }

  Widget _invalid(BuildContext context, String message) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off, size: 48, color: Colors.black38),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      );

  Widget _body(BuildContext context, bool isAnon,
      {required String? teamName, required bool valid}) {
    final who = teamName != null ? 'join $teamName' : 'join a team';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.groups_outlined, size: 48),
        const SizedBox(height: 16),
        Text(
          isAnon
              ? 'You have been invited to $who on Pitch. Sign in to accept.'
              : 'You have been invited to $who. Accept to become a member.',
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
                : Text(teamName != null ? 'Join $teamName' : 'Join team'),
          ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
