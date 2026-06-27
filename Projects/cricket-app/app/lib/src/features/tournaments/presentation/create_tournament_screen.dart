import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/tournament_providers.dart';
import '../data/tournament_repository.dart';

/// Create a tournament. v1 fixes the shape at 2 groups, top 2 of each qualify.
class CreateTournamentScreen extends ConsumerStatefulWidget {
  const CreateTournamentScreen({super.key});

  @override
  ConsumerState<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends ConsumerState<CreateTournamentScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  int _overs = 20;
  String _ballType = 'leather';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(tournamentRepositoryProvider).createTournament(
            name: _name.text.trim(),
            overs: _overs,
            ballType: _ballType,
            city: _city.text.trim(),
          );
      ref.invalidate(tournamentsListProvider);
      if (mounted) context.pushReplacement(Routes.manageTournament(id));
    } catch (e) {
      setState(() => _error = 'Could not create: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveScaffold(
      title: 'New tournament',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Tournament name'),
          ),
          const SizedBox(height: 20),
          Text('Overs', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 10, label: Text('10')),
              ButtonSegment(value: 15, label: Text('15')),
              ButtonSegment(value: 20, label: Text('20')),
            ],
            selected: {_overs},
            onSelectionChanged: (s) => setState(() => _overs = s.first),
          ),
          const SizedBox(height: 20),
          Text('Ball type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'leather', label: Text('Leather')),
              ButtonSegment(value: 'tennis', label: Text('Tennis')),
              ButtonSegment(value: 'tape', label: Text('Tape')),
            ],
            selected: {_ballType},
            onSelectionChanged: (s) => setState(() => _ballType = s.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _city,
            decoration: const InputDecoration(labelText: 'City (optional)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: theme.colorScheme.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text('2 groups, top 2 of each reach the semifinals.',
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                : const Text('Create tournament'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
