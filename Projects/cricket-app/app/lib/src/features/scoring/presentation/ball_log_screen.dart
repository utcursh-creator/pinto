import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';

/// Corrections screen: the ball-by-ball log of the current innings. Each ball
/// can be edited, deleted, or have a missed ball inserted after it - wired to
/// edit_ball / delete_ball / insert_ball. The server re-folds + re-stamps strike,
/// so the scorecard stays correct after any change.
class BallLogScreen extends ConsumerWidget {
  const BallLogScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    final innings = ref.watch(currentInningsProvider(matchId));
    final squad = ref.watch(matchSquadProvider(matchId));

    return AdaptiveScaffold(
      title: 'Ball log',
      body: (match.isLoading || innings.isLoading || squad.isLoading)
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _body(context, ref, match.value, innings.value, squad.value ?? const []),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? match,
    Map<String, dynamic>? innings,
    List<Map<String, dynamic>> squad,
  ) {
    if (innings == null) {
      return const Center(child: Text('No innings to correct yet.'));
    }
    final inningsId = innings['id'] as String;
    final bpo = (match?['balls_per_over'] as num?)?.toInt() ?? 6;
    final battingTeam = innings['batting_team_id'] as String;
    final bowlingTeam = innings['bowling_team_id'] as String;
    final names = {
      for (final s in squad)
        s['team_member_id'] as String: memberName(s['team_members'] as Map<String, dynamic>),
    };
    final deliveries = ref.watch(inningsDeliveriesProvider(inningsId));

    return deliveries.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => Center(child: Text('Could not load deliveries.\n$e')),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No balls bowled yet.'));
        }
        var legalBefore = 0;
        final items = <Widget>[];
        for (final d in rows) {
          final isLegal = (d['is_legal'] as bool?) ?? true;
          final overBall = isLegal
              ? '${legalBefore ~/ bpo}.${legalBefore % bpo + 1}'
              : '${legalBefore ~/ bpo}.${legalBefore % bpo}+';
          if (isLegal) legalBefore++;
          items.add(_BallTile(
            over: overBall,
            outcome: _outcome(d),
            striker: names[d['striker_id']] ?? '-',
            bowler: names[d['bowler_id']] ?? '-',
            onTap: () => _actions(context, ref, inningsId, d, bpo, squad,
                battingTeam, bowlingTeam, names),
          ));
        }
        return ListView(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('Tap a ball to edit, insert, or delete. '
                'The scorecard recomputes automatically.'),
          ),
          ...items,
        ]);
      },
    );
  }

  String _outcome(Map<String, dynamic> d) {
    final w = d['wicket_type'] as String?;
    final parts = <String>[];
    final wides = (d['extra_wides'] as num?)?.toInt() ?? 0;
    final nb = (d['extra_no_ball_penalty'] as num?)?.toInt() ?? 0;
    final byes = (d['extra_byes'] as num?)?.toInt() ?? 0;
    final lb = (d['extra_leg_byes'] as num?)?.toInt() ?? 0;
    final rob = (d['runs_off_bat'] as num?)?.toInt() ?? 0;
    if (wides > 0) parts.add('Wd${wides > 1 ? wides : ''}');
    if (nb > 0) parts.add('Nb${rob > 0 ? '+$rob' : ''}');
    if (byes > 0) parts.add('B$byes');
    if (lb > 0) parts.add('Lb$lb');
    if (nb == 0 && wides == 0 && byes == 0 && lb == 0) parts.add('$rob');
    if (w != null && w != 'retired_not_out') parts.add('W ${w.replaceAll('_', ' ')}');
    return parts.join(' ');
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    String inningsId,
    Map<String, dynamic> d,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit this ball'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Insert a ball after this'),
            onTap: () => Navigator.pop(ctx, 'insert'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete this ball'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final batters = [
      for (final s in squad)
        if (s['team_id'] == battingTeam) s['team_member_id'] as String,
    ];
    final bowlers = [
      for (final s in squad)
        if (s['team_id'] == bowlingTeam) s['team_member_id'] as String,
    ];
    try {
      if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete this ball?'),
            content: const Text('The over and scorecard will recompute.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok ?? false) {
          await ref.read(matchRepositoryProvider).deleteBall(d['id'] as String);
          ref.invalidate(inningsDeliveriesProvider(inningsId));
          ref.invalidate(inningsStateProvider(inningsId));
        }
      } else if (action == 'edit') {
        final res = await _showBallEditor(context,
            initial: _BallEdit.fromDelivery(d), batters: batters, names: names);
        if (res != null) {
          await ref.read(matchRepositoryProvider).editBall(
            deliveryId: d['id'] as String,
            runsOffBat: res.runsOffBat,
            wides: res.wides,
            noBallPenalty: res.noBallPenalty,
            byes: res.byes,
            legByes: res.legByes,
            wicketType: res.wicketType,
            dismissedPlayerId: res.wicketType == null ? null : d['striker_id'] as String?,
            incomingBatterId: res.incomingId,
          );
          ref.invalidate(inningsDeliveriesProvider(inningsId));
          ref.invalidate(inningsStateProvider(inningsId));
        }
      } else if (action == 'insert') {
        final res = await _showBallEditor(context,
            initial: const _BallEdit(),
            batters: batters,
            names: names,
            bowlers: bowlers);
        if (res != null && res.bowlerId != null) {
          await ref.read(matchRepositoryProvider).insertBall(
            inningsId: inningsId,
            afterSeq: (d['seq'] as num).toInt(),
            bowlerId: res.bowlerId!,
            runsOffBat: res.runsOffBat,
            wides: res.wides,
            noBallPenalty: res.noBallPenalty,
            byes: res.byes,
            legByes: res.legByes,
            wicketType: res.wicketType,
            incomingBatterId: res.incomingId,
          );
          ref.invalidate(inningsDeliveriesProvider(inningsId));
          ref.invalidate(inningsStateProvider(inningsId));
        }
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _BallTile extends StatelessWidget {
  const _BallTile({
    required this.over,
    required this.outcome,
    required this.striker,
    required this.bowler,
    required this.onTap,
  });

  final String over;
  final String outcome;
  final String striker;
  final String bowler;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 44,
        child: Text(over, style: const TextStyle(fontFeatures: [])),
      ),
      title: Text(outcome, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$bowler  to  $striker'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// The kind of ball captured by the editor; maps onto record/edit/insert params.
enum _BallType { runs, wide, noBall, bye, legBye }

class _BallEdit {
  const _BallEdit({
    this.type = _BallType.runs,
    this.value = 0,
    this.wicketType,
    this.incomingId,
    this.bowlerId,
  });

  final _BallType type;
  final int value; // off-bat runs for runs/noBall; extra count otherwise
  final String? wicketType;
  final String? incomingId;
  final String? bowlerId;

  int get runsOffBat =>
      (type == _BallType.runs || type == _BallType.noBall) ? value : 0;
  int get wides => type == _BallType.wide ? (value < 1 ? 1 : value) : 0;
  int get noBallPenalty => type == _BallType.noBall ? 1 : 0;
  int get byes => type == _BallType.bye ? value : 0;
  int get legByes => type == _BallType.legBye ? value : 0;

  factory _BallEdit.fromDelivery(Map<String, dynamic> d) {
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    final w = d['wicket_type'] as String?;
    final wide = n('extra_wides');
    final nb = n('extra_no_ball_penalty');
    final byes = n('extra_byes');
    final lb = n('extra_leg_byes');
    final rob = n('runs_off_bat');
    final (type, value) = wide > 0
        ? (_BallType.wide, wide)
        : nb > 0
            ? (_BallType.noBall, rob)
            : byes > 0
                ? (_BallType.bye, byes)
                : lb > 0
                    ? (_BallType.legBye, lb)
                    : (_BallType.runs, rob);
    return _BallEdit(
      type: type,
      value: value,
      wicketType: (w == null || w == 'retired_not_out') ? null : w,
      incomingId: d['incoming_batter_id'] as String?,
    );
  }
}

/// Opens the ball editor sheet. When [bowlers] is non-null the ball is being
/// inserted and a bowler must be chosen. Returns null if cancelled.
Future<_BallEdit?> _showBallEditor(
  BuildContext context, {
  required _BallEdit initial,
  required List<String> batters,
  required Map<String, String> names,
  List<String>? bowlers,
}) {
  return showModalBottomSheet<_BallEdit>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _BallEditorSheet(
      initial: initial,
      batters: batters,
      names: names,
      bowlers: bowlers,
    ),
  );
}

class _BallEditorSheet extends StatefulWidget {
  const _BallEditorSheet({
    required this.initial,
    required this.batters,
    required this.names,
    this.bowlers,
  });

  final _BallEdit initial;
  final List<String> batters;
  final Map<String, String> names;
  final List<String>? bowlers;

  @override
  State<_BallEditorSheet> createState() => _BallEditorSheetState();
}

class _BallEditorSheetState extends State<_BallEditorSheet> {
  late _BallType _type = widget.initial.type;
  late int _value = widget.initial.value;
  late bool _wicket = widget.initial.wicketType != null;
  late String _wicketType = widget.initial.wicketType ?? 'bowled';
  late String? _incoming = widget.initial.incomingId;
  String? _bowler;

  bool get _isInsert => widget.bowlers != null;
  bool get _valid => !_isInsert || _bowler != null;

  static const _typeLabels = {
    _BallType.runs: 'Runs',
    _BallType.wide: 'Wide',
    _BallType.noBall: 'No-ball',
    _BallType.bye: 'Bye',
    _BallType.legBye: 'Leg-bye',
  };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isInsert ? 'Insert a ball' : 'Edit ball',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_isInsert) ...[
                const Text('Bowler'),
                DropdownButton<String>(
                  key: const Key('editor_bowler'),
                  isExpanded: true,
                  value: _bowler,
                  hint: const Text('Choose bowler'),
                  items: [
                    for (final id in widget.bowlers!)
                      DropdownMenuItem(value: id, child: Text(widget.names[id] ?? '-')),
                  ],
                  onChanged: (v) => setState(() => _bowler = v),
                ),
                const SizedBox(height: 12),
              ],
              const Text('Ball type'),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in _BallType.values)
                    ChoiceChip(
                      label: Text(_typeLabels[t]!),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(_type == _BallType.runs
                  ? 'Runs off the bat'
                  : _type == _BallType.noBall
                      ? 'Runs off the bat (plus the no-ball)'
                      : 'Runs'),
              Wrap(
                spacing: 8,
                children: [
                  for (var n = 0; n <= 6; n++)
                    ChoiceChip(
                      label: Text('$n'),
                      selected: _value == n,
                      onSelected: (_) => setState(() => _value = n),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Wicket'),
                value: _wicket,
                onChanged: (v) => setState(() => _wicket = v),
              ),
              if (_wicket) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in const ['bowled', 'caught', 'lbw', 'run_out', 'stumped'])
                      ChoiceChip(
                        label: Text(t.replaceAll('_', ' ')),
                        selected: _wicketType == t,
                        onSelected: (_) => setState(() => _wicketType = t),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Incoming batter'),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _incoming,
                  hint: const Text('Choose'),
                  items: [
                    for (final id in widget.batters)
                      DropdownMenuItem(value: id, child: Text(widget.names[id] ?? '-')),
                  ],
                  onChanged: (v) => setState(() => _incoming = v),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _valid
                      ? () => Navigator.pop(
                            context,
                            _BallEdit(
                              type: _type,
                              value: _value,
                              wicketType: _wicket ? _wicketType : null,
                              incomingId: _wicket ? _incoming : null,
                              bowlerId: _bowler,
                            ),
                          )
                      : null,
                  child: Text(_isInsert ? 'Insert ball' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
