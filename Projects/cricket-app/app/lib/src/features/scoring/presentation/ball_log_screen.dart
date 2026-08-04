import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import '../../../core/ui/app_primitives.dart';
import '../../../core/ui/human_error.dart';
import '../../../core/platform/error_retry.dart';

/// Corrections screen: the ball-by-ball log of the current innings. Each ball
/// can be edited, deleted, or have a missed ball inserted after it - wired to
/// edit_ball / delete_ball / insert_ball. The server re-folds + re-stamps strike,
/// so the scorecard stays correct after any change.
///
/// SCOR-18: the editor captures a delivery's FULL composition (off-bat runs +
/// wide/no-ball + byes + leg-byes + penalty + fielder + who was out), not one
/// mutually-exclusive "type". Event rows (retirements, strike swaps) can only
/// be deleted - they carry no ball to edit.
class BallLogScreen extends ConsumerWidget {
  const BallLogScreen({required this.matchId, super.key});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(matchProvider(matchId));
    final innings = ref.watch(currentInningsProvider(matchId));
    final squad = ref.watch(matchSquadProvider(matchId));

    // Same trap as the console: an errored provider is not loading and has a
    // null value, so this used to fall through to "No innings to correct yet."
    // The balls ARE there - the app just could not read them, and saying
    // otherwise to someone trying to fix a scoring mistake is the worst
    // possible moment to be wrong (whole-system review #2, 2026-07-28).
    final Widget body;
    if (match.isLoading || innings.isLoading || squad.isLoading) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (match.hasError || innings.hasError || squad.hasError) {
      body = Center(
        child: AppEmpty(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the ball log',
          message: humanError(
            (match.error ?? innings.error ?? squad.error)!,
            fallback: 'Check your connection and try again - nothing already '
                'recorded is lost.',
          ),
          actionLabel: 'Try again',
          onAction: () {
            ref.invalidate(matchProvider(matchId));
            ref.invalidate(currentInningsProvider(matchId));
            ref.invalidate(matchSquadProvider(matchId));
          },
        ),
      );
    } else {
      body =
          _body(context, ref, match.value, innings.value, squad.value ?? const []);
    }

    return AdaptiveScaffold(
      title: 'Ball log',
      body: body,
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
      error: (e, _) => ErrorRetry(
        message: humanError(e, fallback: 'Could not load deliveries.'),
        onRetry: () => ref.invalidate(inningsDeliveriesProvider(inningsId)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('No balls bowled yet.'));
        }
        var legalBefore = 0;
        final items = <Widget>[];
        for (final d in rows) {
          final isEvent = d['event_kind'] != null;
          final isLegal = !isEvent && ((d['is_legal'] as bool?) ?? true);
          final overBall = isEvent
              ? '-'
              : isLegal
                  ? '${legalBefore ~/ bpo}.${legalBefore % bpo + 1}'
                  : '${legalBefore ~/ bpo}.${legalBefore % bpo}+';
          if (isLegal) legalBefore++;
          items.add(_BallTile(
            over: overBall,
            outcome: _outcome(d, names),
            striker: names[d['striker_id']] ?? '-',
            bowler: isEvent ? 'between balls' : (names[d['bowler_id']] ?? '-'),
            onTap: () => _actions(context, ref, inningsId, d, rows, bpo, squad,
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

  String _outcome(Map<String, dynamic> d, Map<String, String> names) {
    // v14 event rows are not balls - describe the event itself
    final event = d['event_kind'] as String?;
    if (event == 'strike_swap') return 'Strike swapped';
    if (event == 'retirement') {
      final who = names[d['dismissed_player_id']] ?? 'Batter';
      final out = d['wicket_type'] != 'retired_not_out';
      return '$who retired ${out ? 'out' : 'hurt'}';
    }
    final w = d['wicket_type'] as String?;
    final parts = <String>[];
    final wides = (d['extra_wides'] as num?)?.toInt() ?? 0;
    final nb = (d['extra_no_ball_penalty'] as num?)?.toInt() ?? 0;
    final byes = (d['extra_byes'] as num?)?.toInt() ?? 0;
    final lb = (d['extra_leg_byes'] as num?)?.toInt() ?? 0;
    final pen = (d['extra_penalty'] as num?)?.toInt() ?? 0;
    final rob = (d['runs_off_bat'] as num?)?.toInt() ?? 0;
    if (wides > 0) parts.add('Wd${wides > 1 ? wides : ''}');
    if (nb > 0) parts.add('Nb${rob > 0 ? '+$rob' : ''}');
    if (byes > 0) parts.add('B$byes');
    if (lb > 0) parts.add('Lb$lb');
    if (pen > 0) parts.add('Pen+$pen');
    if (nb == 0 && wides == 0 && byes == 0 && lb == 0 && pen == 0) {
      parts.add('$rob');
    } else if (nb == 0 && rob > 0) {
      parts.add('+$rob bat');
    }
    if (w != null && w != 'retired_not_out') parts.add('W ${w.replaceAll('_', ' ')}');
    return parts.join(' ');
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    String inningsId,
    Map<String, dynamic> d,
    List<Map<String, dynamic>> allRows,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
  ) async {
    final isEvent = d['event_kind'] != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!isEvent)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit this ball'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
          if (!isEvent)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Insert a ball after this'),
              onTap: () => Navigator.pop(ctx, 'insert'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(isEvent ? 'Remove this event' : 'Delete this ball'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    // SCOR-2/5: a batter dismissed or retired on ANOTHER ball cannot be
    // offered as this ball's incoming batter.
    final outElsewhere = <String>{
      for (final r in allRows)
        if (r['id'] != d['id'] && r['wicket_type'] != null)
          (r['wicket_type'] == 'run_out' ||
                  r['wicket_type'] == 'obstructing' ||
                  r['event_kind'] == 'retirement')
              ? (r['dismissed_player_id'] as String? ?? '')
              : (r['striker_id'] as String? ?? ''),
    }..remove('');
    final batters = [
      for (final s in squad)
        if (s['team_id'] == battingTeam &&
            !outElsewhere.contains(s['team_member_id']))
          s['team_member_id'] as String,
    ];
    final fielders = [
      for (final s in squad)
        if (s['team_id'] == bowlingTeam) s['team_member_id'] as String,
    ];
    final bowlers = fielders;
    try {
      if (action == 'delete') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isEvent ? 'Remove this event?' : 'Delete this ball?'),
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
            initial: _BallEdit.fromDelivery(d),
            batters: batters,
            fielders: fielders,
            names: names,
            strikerId: d['striker_id'] as String?,
            nonStrikerId: d['non_striker_id'] as String?);
        if (res != null) {
          await ref.read(matchRepositoryProvider).editBall(
            deliveryId: d['id'] as String,
            runsOffBat: res.runsOffBat,
            wides: res.wides,
            noBallPenalty: res.noBallPenalty,
            byes: res.byes,
            legByes: res.legByes,
            penalty: res.penalty,
            noballSecondaryKind: res.noballSecondaryKind,
            wicketType: res.wicketType,
            dismissedPlayerId: res.dismissedId,
            incomingBatterId: res.incomingId,
            fielderId: res.fielderId,
            // The ball HAD a wicket and the scorer switched it off. Without this
            // the COALESCE patch keeps the old dismissal, so a mis-tapped wicket
            // could never be taken back - the batter stayed out on the scorecard
            // forever (whole-system review #2).
            clearWicket: (d['wicket_type'] as String?) != null &&
                res.wicketType == null,
          );
          ref.invalidate(inningsDeliveriesProvider(inningsId));
          ref.invalidate(inningsStateProvider(inningsId));
        }
      } else if (action == 'insert') {
        final res = await _showBallEditor(context,
            initial: const _BallEdit(),
            batters: batters,
            fielders: fielders,
            names: names,
            strikerId: d['striker_id'] as String?,
            nonStrikerId: d['non_striker_id'] as String?,
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
            penalty: res.penalty,
            noballSecondaryKind: res.noballSecondaryKind,
            wicketType: res.wicketType,
            dismissedPlayerId: res.dismissedId,
            incomingBatterId: res.incomingId,
            fielderId: res.fielderId,
          );
          ref.invalidate(inningsDeliveriesProvider(inningsId));
          ref.invalidate(inningsStateProvider(inningsId));
        }
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(humanError(e))));
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

/// SCOR-18: the delivery's full composition - every field independent, exactly
/// like the columns edit_ball/insert_ball accept.
class _BallEdit {
  const _BallEdit({
    this.runsOffBat = 0,
    this.wides = 0,
    this.noBallPenalty = 0,
    this.byes = 0,
    this.legByes = 0,
    this.penalty = 0,
    this.wicketType,
    this.dismissedId,
    this.incomingId,
    this.fielderId,
    this.bowlerId,
  });

  final int runsOffBat;
  final int wides;
  final int noBallPenalty;
  final int byes;
  final int legByes;
  final int penalty;
  final String? wicketType;
  final String? dismissedId;
  final String? incomingId;
  final String? fielderId;
  final String? bowlerId;

  /// Must emit public.noball_secondary_kind values, which are SINGULAR:
  /// ('off_bat','bye','leg_bye'). This used to emit the plural UI spellings, so
  /// correcting a no-ball that went for byes was a hard 400 - the same defect
  /// the scoring console had (penetration review 2026-07-07).
  String? get noballSecondaryKind => noBallPenalty > 0
      ? (runsOffBat > 0
          ? 'off_bat'
          : byes > 0
              ? 'bye'
              : legByes > 0
                  ? 'leg_bye'
                  : null)
      : null;

  factory _BallEdit.fromDelivery(Map<String, dynamic> d) {
    int n(String k) => (d[k] as num?)?.toInt() ?? 0;
    final w = d['wicket_type'] as String?;
    return _BallEdit(
      runsOffBat: n('runs_off_bat'),
      wides: n('extra_wides'),
      noBallPenalty: n('extra_no_ball_penalty'),
      byes: n('extra_byes'),
      legByes: n('extra_leg_byes'),
      penalty: n('extra_penalty'),
      wicketType: (w == null || w == 'retired_not_out') ? null : w,
      dismissedId: d['dismissed_player_id'] as String?,
      incomingId: d['incoming_batter_id'] as String?,
      fielderId: d['fielder_id'] as String?,
    );
  }
}

/// Opens the ball editor sheet. When [bowlers] is non-null the ball is being
/// inserted and a bowler must be chosen. Returns null if cancelled.
Future<_BallEdit?> _showBallEditor(
  BuildContext context, {
  required _BallEdit initial,
  required List<String> batters,
  required List<String> fielders,
  required Map<String, String> names,
  String? strikerId,
  String? nonStrikerId,
  List<String>? bowlers,
}) {
  return showModalBottomSheet<_BallEdit>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _BallEditorSheet(
      initial: initial,
      batters: batters,
      fielders: fielders,
      names: names,
      strikerId: strikerId,
      nonStrikerId: nonStrikerId,
      bowlers: bowlers,
    ),
  );
}

class _BallEditorSheet extends StatefulWidget {
  const _BallEditorSheet({
    required this.initial,
    required this.batters,
    required this.fielders,
    required this.names,
    this.strikerId,
    this.nonStrikerId,
    this.bowlers,
  });

  final _BallEdit initial;
  final List<String> batters;
  final List<String> fielders;
  final Map<String, String> names;
  final String? strikerId;
  final String? nonStrikerId;
  final List<String>? bowlers;

  @override
  State<_BallEditorSheet> createState() => _BallEditorSheetState();
}

class _BallEditorSheetState extends State<_BallEditorSheet> {
  late int _runs = widget.initial.runsOffBat;
  // 'legal' | 'wide' | 'no_ball' - a genuinely exclusive cricket fact
  late String _delivery = widget.initial.wides > 0
      ? 'wide'
      : widget.initial.noBallPenalty > 0
          ? 'no_ball'
          : 'legal';
  late int _wideRuns = widget.initial.wides;
  late int _byes = widget.initial.byes;
  late int _legByes = widget.initial.legByes;
  late bool _penalty = widget.initial.penalty > 0;
  late bool _wicket = widget.initial.wicketType != null;
  late String _wicketType = widget.initial.wicketType ?? 'bowled';
  late String? _incoming = widget.initial.incomingId;
  late String? _fielder = widget.initial.fielderId;
  late String _whoOut = widget.initial.dismissedId != null &&
          widget.initial.dismissedId == widget.nonStrikerId
      ? 'non_striker'
      : 'striker';
  String? _bowler;

  bool get _isInsert => widget.bowlers != null;
  bool get _valid => !_isInsert || _bowler != null;

  static bool _needsWhoOut(String t) =>
      t == 'run_out' || t == 'obstructing' || t == 'retired_out';
  static bool _needsFielder(String t) =>
      t == 'caught' || t == 'stumped' || t == 'run_out';

  Widget _stepper(String label, int value, ValueChanged<int> set, {int min = 0}) =>
      Row(children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => setState(() => set(value - 1)) : null,
        ),
        Text('$value', style: const TextStyle(fontSize: 16)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => setState(() => set(value + 1)),
        ),
      ]);

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
              const Text('Delivery'),
              Wrap(
                spacing: 8,
                children: [
                  for (final (v, l) in const [
                    ('legal', 'Legal'),
                    ('wide', 'Wide'),
                    ('no_ball', 'No-ball'),
                  ])
                    ChoiceChip(
                      label: Text(l),
                      selected: _delivery == v,
                      onSelected: (_) => setState(() {
                        _delivery = v;
                        if (v == 'wide') {
                          _runs = 0; // nothing comes off the bat on a wide
                          if (_wideRuns < 1) _wideRuns = 1;
                        }
                      }),
                    ),
                ],
              ),
              if (_delivery == 'wide') ...[
                const SizedBox(height: 8),
                _stepper('Wide runs (1 = just the wide)', _wideRuns,
                    (v) => _wideRuns = v,
                    min: 1),
              ] else ...[
                const SizedBox(height: 12),
                const Text('Runs off the bat'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var n = 0; n <= 6; n++)
                      ChoiceChip(
                        label: Text('$n'),
                        selected: _runs == n,
                        onSelected: (_) => setState(() => _runs = n),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _stepper('Byes', _byes, (v) => _byes = v),
              _stepper('Leg-byes', _legByes, (v) => _legByes = v),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('+5 penalty runs'),
                value: _penalty,
                onChanged: (v) => setState(() => _penalty = v),
              ),
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
                    for (final t in const [
                      'bowled', 'caught', 'lbw', 'run_out', 'stumped',
                      'hit_wicket', 'obstructing', 'hit_ball_twice',
                    ])
                      ChoiceChip(
                        label: Text(t.replaceAll('_', ' ')),
                        selected: _wicketType == t,
                        onSelected: (_) => setState(() => _wicketType = t),
                      ),
                  ],
                ),
                if (_needsWhoOut(_wicketType)) ...[
                  const SizedBox(height: 8),
                  const Text('Who was out?'),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: Text(widget.names[widget.strikerId] ?? 'Striker'),
                      selected: _whoOut == 'striker',
                      onSelected: (_) => setState(() => _whoOut = 'striker'),
                    ),
                    ChoiceChip(
                      label: Text(
                          widget.names[widget.nonStrikerId] ?? 'Non-striker'),
                      selected: _whoOut == 'non_striker',
                      onSelected: (_) => setState(() => _whoOut = 'non_striker'),
                    ),
                  ]),
                ],
                if (_needsFielder(_wicketType)) ...[
                  const SizedBox(height: 8),
                  const Text('Fielder'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _fielder,
                    hint: const Text('Choose (optional)'),
                    items: [
                      for (final id in widget.fielders)
                        DropdownMenuItem(
                            value: id, child: Text(widget.names[id] ?? '-')),
                    ],
                    onChanged: (v) => setState(() => _fielder = v),
                  ),
                ],
                const SizedBox(height: 8),
                const Text('Incoming batter'),
                DropdownButton<String>(
                  isExpanded: true,
                  value: widget.batters.contains(_incoming) ? _incoming : null,
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
                              runsOffBat: _delivery == 'wide' ? 0 : _runs,
                              wides: _delivery == 'wide' ? _wideRuns : 0,
                              noBallPenalty: _delivery == 'no_ball' ? 1 : 0,
                              byes: _byes,
                              legByes: _legByes,
                              penalty: _penalty ? 5 : 0,
                              wicketType: _wicket ? _wicketType : null,
                              dismissedId: _wicket
                                  ? (_needsWhoOut(_wicketType) &&
                                          _whoOut == 'non_striker'
                                      ? widget.nonStrikerId
                                      : widget.strikerId)
                                  : null,
                              incomingId: _wicket ? _incoming : null,
                              fielderId: _wicket && _needsFielder(_wicketType)
                                  ? _fielder
                                  : null,
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
