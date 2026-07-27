import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/data/identity_providers.dart';
import '../data/tournament_repository.dart';
import '../../../core/ui/human_error.dart';

/// Opens from a tournament join link (`/join-tournament/:token`). A team admin
/// picks one of THEIR teams and enters it into the tournament - their act of
/// redeeming is the consent (SEC-8, CricHeroes-style self-registration). An
/// anonymous visitor is asked to sign in first.
class JoinTournamentScreen extends ConsumerStatefulWidget {
  const JoinTournamentScreen({required this.token, super.key});

  final String token;

  @override
  ConsumerState<JoinTournamentScreen> createState() =>
      _JoinTournamentScreenState();
}

class _JoinTournamentScreenState extends ConsumerState<JoinTournamentScreen> {
  String? _teamId;
  bool _busy = false;
  String? _message;

  Future<void> _join() async {
    if (_teamId == null) {
      setState(() => _message = 'Pick which of your teams to enter.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final tournamentId = await ref
          .read(tournamentRepositoryProvider)
          .joinTournamentWithToken(widget.token, _teamId!, 'A');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Your team is entered in the tournament')),
      );
      context.go(Routes.tournamentPage(tournamentId));
    } catch (e) {
      setState(() => _message = _humanError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _humanError(String raw) {
    if (raw.contains('admin of the team')) {
      return 'You can only enter a team you manage. Pick one of your own teams.';
    }
    if (raw.contains('registration is closed')) {
      return 'Registration for this tournament has closed.';
    }
    if (raw.contains('not found or already used')) {
      return 'This invite has already been used or is no longer valid.';
    }
    return 'Could not join: $raw';
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = ref.watch(isAnonymousProvider);
    return AdaptiveScaffold(
      // A shared link cold-starts here, outside the tab shell: offer a way
      // into the app rather than leaving the visitor on an island.
      onEnterApp: () => context.go(Routes.discover),
      title: 'Join tournament',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: isAnon ? _anon(context) : _teamPicker(context),
        ),
      ),
    );
  }

  Widget _anon(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_outlined, size: 48),
          const SizedBox(height: 16),
          const Text(
            'You have been invited to add your team to a tournament on Pitch. '
            'Sign in to enter your team.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.push(
                Routes.signInThenReturnTo(Routes.joinTournament(widget.token))),
            child: const Text('Sign in to join'),
          ),
        ],
      );

  Widget _teamPicker(BuildContext context) {
    final teams = ref.watch(myTeamsProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.emoji_events_outlined, size: 48),
        const SizedBox(height: 16),
        const Text(
          'Add your team to this tournament. Pick the team you want to enter '
          '(you must be a team admin).',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        teams.when(
          loading: () => const CircularProgressIndicator.adaptive(),
          error: (e, _) => Text(humanError(e, fallback: 'Could not load your teams.')),
          data: (rows) {
            final myTeams = [
              for (final r in rows)
                if (r['teams'] is Map) r['teams'] as Map<String, dynamic>,
            ];
            if (myTeams.isEmpty) {
              return Column(
                children: [
                  const Text('You are not an admin of any team yet.'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.push(Routes.createTeam),
                    child: const Text('Create a team first'),
                  ),
                ],
              );
            }
            return Column(
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: _teamId,
                  hint: const Text('Choose your team'),
                  items: [
                    for (final t in myTeams)
                      DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text((t['name'] as String?) ?? 'Team'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _teamId = v),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _join,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator.adaptive(strokeWidth: 2),
                        )
                      : const Text('Add my team'),
                ),
              ],
            );
          },
        ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}
