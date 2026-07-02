import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _venue = TextEditingController();
  final _overs = TextEditingController(text: '20');
  String _ballType = 'leather';
  DateTime? _startsOn;
  DateTime? _endsOn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _venue.dispose();
    _overs.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'A name is required.');
      return;
    }
    final overs = int.tryParse(_overs.text.trim());
    if (overs == null || overs < 5 || overs > 50) {
      setState(() => _error = 'Overs must be a number from 5 to 50.');
      return;
    }
    if (_startsOn != null && _endsOn != null && _endsOn!.isBefore(_startsOn!)) {
      setState(() => _error = 'The end date cannot be before the start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(tournamentRepositoryProvider).createTournament(
            name: _name.text.trim(),
            overs: overs,
            ballType: _ballType,
            city: _city.text.trim(),
            venue: _venue.text.trim(),
            startsOn: _startsOn,
            endsOn: _endsOn,
          );
      ref.invalidate(tournamentsListProvider);
      if (mounted) context.pushReplacement(Routes.manageTournament(id));
    } catch (e) {
      setState(() => _error = 'Could not create: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _startsOn : _endsOn) ?? _startsOn ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startsOn = picked;
      } else {
        _endsOn = picked;
      }
    });
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Tournament name'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _overs,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Overs per match',
              helperText: '5 to 50',
            ),
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
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _venue,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Venue / ground (optional)'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(start: true),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_startsOn == null ? 'Start date' : _fmt(_startsOn!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickDate(start: false),
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_endsOn == null ? 'End date' : _fmt(_endsOn!)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
