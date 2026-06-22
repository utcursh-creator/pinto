import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';

/// Hand scoring to another registered member of either team. After a successful
/// transfer the caller is no longer the scorer, so we pop back out of the
/// console.
class TransferScorerScreen extends ConsumerStatefulWidget {
  const TransferScorerScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<TransferScorerScreen> createState() =>
      _TransferScorerScreenState();
}

class _TransferScorerScreenState extends ConsumerState<TransferScorerScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _hand(String profileId, String name) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(matchRepositoryProvider).transferScorer(
            matchId: widget.matchId,
            newScorerId: profileId,
          );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Scoring handed to $name')));
      // Leave the scorer flow: pop the transfer screen and the console.
      context.pop();
      if (context.canPop()) context.pop();
    } on PostgrestException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(matchScorerCandidatesProvider(widget.matchId));
    return AdaptiveScaffold(
      title: 'Hand over scoring',
      body: candidates.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text('Could not load members.\n$e')),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No other registered players on either team to hand scoring to.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Pick who takes over scoring from here. You will lose write '
                    'access once they accept the handover.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                for (final r in rows)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(r['name'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _hand(
                      r['profile_id'] as String,
                      r['name'] as String,
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
