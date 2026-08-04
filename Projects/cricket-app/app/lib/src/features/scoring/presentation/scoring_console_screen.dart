import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../data/match_repository.dart';
import 'wagon_field.dart';
import '../../../core/ui/app_primitives.dart';
import '../../../core/ui/human_error.dart';
import '../../tournaments/data/tournament_providers.dart';
import '../../../core/supabase/supabase_providers.dart';

/// The live ball-by-ball scorer console. Reads compute_innings_state for the
/// score/strike, records deliveries via record_ball, re-folds after each ball.
class ScoringConsoleScreen extends ConsumerStatefulWidget {
  const ScoringConsoleScreen({required this.matchId, super.key});

  final String matchId;

  @override
  ConsumerState<ScoringConsoleScreen> createState() =>
      _ScoringConsoleScreenState();
}

class _ScoringConsoleScreenState extends ConsumerState<ScoringConsoleScreen> {
  String? _bowlerId; // selected for the current over
  String? _lastOverBowlerId; // who bowled the over that just ended (SCOR-15)
  bool _busy = false;
  bool _breakMarked = false; // SCOR-1: innings-break status written once
  bool _undoBusy = false; // Undo needs its own guard (a double tap deleted 2)

  MatchRepository get _repo => ref.read(matchRepositoryProvider);

  Map<String, String> _names(List<Map<String, dynamic>> squad) => {
        for (final s in squad)
          s['team_member_id'] as String:
              memberName(s['team_members'] as Map<String, dynamic>),
      };

  /// [legalBefore] is what the fold reported BEFORE this delivery.
  ///
  /// An over ends when a delivery COMPLETES it, not merely when the legal-ball
  /// count happens to sit on a multiple of the over. A wide or a no-ball adds
  /// no legal ball, so the count does not move - and immediately after an over
  /// ends it is already a multiple. Testing `legal % bpo == 0` alone therefore
  /// declared the over finished a second time on any first-ball wide, cleared
  /// the bowler, and filed the man who had just started as `_lastOverBowlerId`
  /// - which the picker renders as "Bowled last over" and refuses to select.
  /// The scorer was left unable to nominate the bowler who was mid-over
  /// (whole-system review #2, 2026-07-28).
  Future<void> _afterBall(String inningsId, int bpo, int legalBefore) async {
    ref.invalidate(inningsStateProvider(inningsId));
    final fresh = await ref.read(inningsStateProvider(inningsId).future);
    final legal = (fresh['legal_balls'] as num?)?.toInt() ?? 0;
    if (legal > legalBefore && legal % bpo == 0) {
      // over completed by the current bowler - the next over needs a new one
      if (mounted) {
        setState(() {
          _lastOverBowlerId = _bowlerId;
          _bowlerId = null;
        });
      }
    }
  }

  Future<void> _record(
    String inningsId,
    int bpo, {
    int runs = 0,
    int wides = 0,
    int noBall = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    bool isOverthrow = false,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedId,
    String? incomingId,
    String? fielderId,
    bool? crossed,
    int? lastSeq,
  }) async {
    if (_bowlerId == null || _busy) return;
    setState(() => _busy = true);
    // capture BEFORE the delivery - a wide leaves this unchanged, which is
    // exactly how _afterBall tells "the over ended" from "it already had"
    final legalBefore = (ref.read(inningsStateProvider(inningsId)).value?[
            'legal_balls'] as num?)
        ?.toInt() ??
        0;
    try {
      final res = await _repo.recordBall(
        inningsId: inningsId,
        bowlerId: _bowlerId!,
        runsOffBat: runs,
        wides: wides,
        noBallPenalty: noBall,
        byes: byes,
        legByes: legByes,
        penalty: penalty,
        isOverthrow: isOverthrow,
        noballSecondaryKind: noballSecondaryKind,
        wicketType: wicketType,
        dismissedPlayerId: dismissedId,
        incomingBatterId: incomingId,
        fielderId: fielderId,
        crossed: crossed,
        // SCOR-24: the version this tap was decided against
        expectedLastSeq: lastSeq,
      );
      await _afterBall(inningsId, bpo, legalBefore);
      // the recording is DONE here - drop the busy state BEFORE the wagon
      // prompt, or the progress bar animates under the open sheet forever
      if (mounted) setState(() => _busy = false);
      if (res.wagonApplicable && res.deliveryId != null && mounted) {
        await _promptWagon(res.deliveryId!,
            runs: runs, wicket: wicketType != null);
      }
    } catch (e) {
      final raw = '$e';
      if (raw.contains('changed on another device')) {
        ref.invalidate(inningsStateProvider(inningsId));
        _toast('The innings changed on another device - refreshed, try again.');
      } else {
        // humanError keeps our own P0001 copy ("bowler cannot bowl consecutive
        // overs") and scrubs Postgres internals, which used to reach the
        // scorer verbatim and read as a crash.
        _toast(humanError(e,
            fallback: 'Could not record that ball. Try again.'));
      }
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  /// After a directional bat shot, ask the scorer where the ball went.
  /// SCOR-17: shows what is being placed, cannot be swipe-dismissed by
  /// accident (explicit Skip only), and a failed save is said out loud.
  Future<void> _promptWagon(String deliveryId,
      {int runs = 0, bool wicket = false}) async {
    final ballLabel = wicket
        ? 'the wicket ball'
        : runs == 0
            ? 'the dot ball'
            : '$runs run${runs == 1 ? '' : 's'}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Where did $ballLabel go?',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Skip'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: WagonField(
                  onTap: (x, y, zone) async {
                    try {
                      await _repo.setDeliveryWagon(
                        deliveryId: deliveryId,
                        x: x,
                        y: y,
                        zone: zone,
                      );
                    } catch (e) {
                      _toast(humanError(e, fallback: 'Shot not saved.'));
                    }
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m != null) m.showSnackBar(SnackBar(content: Text(msg)));
  }

  /// SCOR-7: the full delivery composer for everything the quick pad can't
  /// express - wide+N, no-ball with off-bat/bye/leg-bye runs, N byes/leg-byes,
  /// 5s/7s (off-bat count), overthrows, and the 5-run penalty on any ball.
  Future<void> _extras(String inningsId, int bpo, {int? lastSeq}) async {
    String type = 'wide';
    String nbKind = 'off_bat'; // what the runs off a no-ball were
    int runs = 0;
    bool overthrow = false;
    bool penalty = false;
    String labelFor(String t) => switch (t) {
          'wide' => 'Wide',
          'no_ball' => 'No-ball',
          'byes' => 'Byes',
          'leg_byes' => 'Leg-byes',
          'off_bat' => 'Runs',
          _ => t,
        };
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final needsRun = type == 'byes' || type == 'leg_byes';
          final hint = switch (type) {
            'wide' => 'Extra runs run off the wide (the wide itself counts 1)',
            'no_ball' => 'Runs scored off the no-ball (the no-ball counts 1)',
            'byes' => 'Byes run',
            'leg_byes' => 'Leg-byes run',
            'off_bat' => 'Runs off the bat (5s, 7s, overthrow totals)',
            _ => '',
          };
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
                    const Text('This ball was'),
                    Wrap(spacing: 8, children: [
                      for (final t in const [
                        'wide', 'no_ball', 'byes', 'leg_byes', 'off_bat',
                      ])
                        ChoiceChip(
                          label: Text(labelFor(t)),
                          selected: type == t,
                          onSelected: (_) => setSheet(() => type = t),
                        ),
                    ]),
                    if (type == 'no_ball') ...[
                      const SizedBox(height: 10),
                      const Text('The runs came from'),
                      Wrap(spacing: 8, children: [
                        for (final (k, l) in const [
                          ('off_bat', 'The bat'),
                          ('byes', 'Byes'),
                          ('leg_byes', 'Leg-byes'),
                        ])
                          ChoiceChip(
                            label: Text(l),
                            selected: nbKind == k,
                            onSelected: (_) => setSheet(() => nbKind = k),
                          ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: Text(hint)),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: runs > 0 ? () => setSheet(() => runs--) : null,
                      ),
                      Text('$runs', style: const TextStyle(fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setSheet(() => runs++),
                      ),
                    ]),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Includes overthrows'),
                      value: overthrow,
                      onChanged: (v) => setSheet(() => overthrow = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('+5 penalty runs on this ball'),
                      subtitle: const Text(
                          'Ball hit a helmet, deliberate short run, etc.'),
                      value: penalty,
                      onChanged: (v) => setSheet(() => penalty = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: (needsRun && runs < 1)
                          ? null
                          : () => Navigator.pop(context, true),
                      child: const Text('Record'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (ok ?? false) {
      final pen = penalty ? 5 : 0;
      switch (type) {
        case 'wide':
          await _record(inningsId, bpo,
              wides: 1 + runs,
              penalty: pen,
              isOverthrow: overthrow,
              lastSeq: lastSeq);
        case 'no_ball':
          await _record(inningsId, bpo,
              noBall: 1,
              runs: nbKind == 'off_bat' ? runs : 0,
              byes: nbKind == 'byes' ? runs : 0,
              legByes: nbKind == 'leg_byes' ? runs : 0,
              noballSecondaryKind: runs > 0 ? _nbKindEnum(nbKind) : null,
              penalty: pen,
              isOverthrow: overthrow,
              lastSeq: lastSeq);
        case 'byes':
          await _record(inningsId, bpo,
              byes: runs, penalty: pen, isOverthrow: overthrow, lastSeq: lastSeq);
        case 'leg_byes':
          await _record(inningsId, bpo,
              legByes: runs,
              penalty: pen,
              isOverthrow: overthrow,
              lastSeq: lastSeq);
        case 'off_bat':
          await _record(inningsId, bpo,
              runs: runs, penalty: pen, isOverthrow: overthrow, lastSeq: lastSeq);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = ref.watch(matchProvider(widget.matchId));
    final innings = ref.watch(currentInningsProvider(widget.matchId));
    final squad = ref.watch(matchSquadProvider(widget.matchId));

    return AdaptiveScaffold(
      title: 'Live scoring',
      actions: [
        IconButton(
          icon: const Icon(Icons.edit_note),
          tooltip: 'Ball log / corrections',
          onPressed: () => context.push(Routes.ballLog(widget.matchId)),
        ),
        IconButton(
          icon: const Icon(Icons.swap_horiz),
          tooltip: 'Hand over scoring',
          onPressed: () =>
              context.push(Routes.transferScorer(widget.matchId)),
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'Watch (public view)',
          onPressed: () => context.push(Routes.viewMatch(widget.matchId)),
        ),
      ],
      body: (match.isLoading || innings.isLoading || squad.isLoading)
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _content(
              match.value,
              innings.value,
              squad.value ?? const [],
              ref.watch(matchTeamNamesProvider(widget.matchId)).value ??
                  const <String, String>{},
            ),
    );
  }

  Widget _content(
    Map<String, dynamic>? match,
    Map<String, dynamic>? innings,
    List<Map<String, dynamic>> squad,
    Map<String, String> teamNames,
  ) {
    if (innings == null) {
      return const Center(child: Text('No innings yet. Finish setup first.'));
    }
    final inningsId = innings['id'] as String;
    final bpo = (match?['balls_per_over'] as num?)?.toInt() ?? 6;
    final bowlingTeam = innings['bowling_team_id'] as String;
    final battingTeam = innings['batting_team_id'] as String;
    final names = _names(squad);
    final state = ref.watch(inningsStateProvider(inningsId));

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      // CRITICAL (whole-system review #2): this was a bare message. A Riverpod
      // provider CACHES its failure, so one dropped packet while the scorer is
      // mid-over left the console showing "Could not load score." with no way
      // back - no retry, no refresh, and the cached error meant reopening the
      // screen showed it again. The scorer's only recourse was to kill the app,
      // in the middle of a live match.
      error: (e, _) => Center(
        child: AppEmpty(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the score',
          message: humanError(e,
              fallback: 'Check your connection and try again - nothing you '
                  'have already recorded is lost.'),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(inningsStateProvider(inningsId)),
        ),
      ),
      data: (s) {
        final runs = (s['runs'] as num?)?.toInt() ?? 0;
        final wkts = (s['wickets'] as num?)?.toInt() ?? 0;
        final over = s['over']?.toString() ?? '0.0';
        final strikerId = s['striker_id'] as String?;
        final nonStrikerId = s['non_striker_id'] as String?;
        final target = innings['target'] as int?;
        final ended = s['innings_status'] == 'completed';
        final matchDone = match?['status'] == 'complete' ||
            match?['status'] == 'abandoned';
        // Chase line: "Need R off B  (RRR x.xx)".
        final runsReq = (s['runs_required'] as num?)?.toInt();
        final ballsRem = (s['balls_remaining'] as num?)?.toInt();
        final rrr = s['rrr'];
        final crr = s['crr']; // SCOR-21
        final orphans = (s['orphaned_deliveries'] as List?) ?? const [];

        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFF0F2E26),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$runs/$wkts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Over $over'
                    '${crr != null ? '   -   CRR $crr' : ''}'
                    '${target != null ? '   -   target $target' : ''}',
                    style: const TextStyle(color: Color(0xFF7DD3B9)),
                  ),
                  if (target != null && !ended && runsReq != null && ballsRem != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Need $runsReq off $ballsRem'
                        '${rrr != null ? '   (RRR $rrr)' : ''}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            // SCOR-9: deliveries recorded past the innings end are ignored by
            // the fold - tell the scorer instead of silently dropping them.
            if (orphans.isNotEmpty)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF3CD),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                child: Text(
                  '${orphans.length} ball${orphans.length == 1 ? '' : 's'} '
                  'recorded after the innings ended - remove or fix them in '
                  'the ball log.',
                  style: const TextStyle(color: Color(0xFF8A6D00)),
                ),
              ),
            if (s['free_hit_active'] == true && !ended)
              Container(
                width: double.infinity,
                color: const Color(0xFFFFF3CD),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                child: const Text('FREE HIT',
                    style: TextStyle(
                        color: Color(0xFF8A6D00), fontWeight: FontWeight.bold)),
              ),
            if (ended)
              Expanded(
                child: _endPanel(
                  s: s,
                  innings: innings,
                  squad: squad,
                  teamNames: teamNames,
                  battingTeam: battingTeam,
                  bowlingTeam: bowlingTeam,
                  target: target,
                  matchDone: matchDone,
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('On strike: ${names[strikerId] ?? '-'}  *'),
                    ),
                    Expanded(child: Text(names[nonStrikerId] ?? '-')),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                title: Text(
                  _bowlerId == null
                      ? 'Select a bowler to start the over'
                      : 'Bowling: ${names[_bowlerId] ?? '-'}',
                ),
                trailing: TextButton(
                  onPressed: () =>
                      _pickBowler(squad, bowlingTeam, names, s, bpo),
                  child: Text(_bowlerId == null ? 'Pick' : 'Change'),
                ),
              ),
              // SCOR-19: recording in flight is visible, not a dead pad
              if (_busy)
                const LinearProgressIndicator(minHeight: 2)
              else
                const Divider(height: 1),
              Expanded(
                // SCOR-19: a tap on the disabled pad explains itself instead
                // of being swallowed by the AbsorbPointer.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: (_bowlerId == null && !_busy)
                      ? () {
                          _toast('Pick a bowler to start the over');
                          _pickBowler(squad, bowlingTeam, names, s, bpo);
                        }
                      : null,
                  child: AbsorbPointer(
                    absorbing: _bowlerId == null || _busy,
                    child: Opacity(
                      opacity: _bowlerId == null ? 0.4 : 1,
                      child: _pad(inningsId, bpo, squad, battingTeam,
                          bowlingTeam, names, s),
                    ),
                  ),
                ),
              ),
              // Between-ball actions live OUTSIDE the AbsorbPointer. They used
              // to sit inside _pad, which meant Undo was dead whenever no bowler
              // was selected - i.e. at the start of every over, the exact moment
              // a scorer reaches for Undo after a mis-tap ended the last one
              // (penetration review 2026-07-07).
              _betweenBallRow(inningsId, bpo, squad, battingTeam, names, s),
            ],
          ],
        );
      },
    );
  }

  /// Shown when the current innings has ended. Three cases:
  ///  * match already resolved -> just offer the scorecard;
  ///  * 1st innings done (no target) -> innings break, start the chase;
  ///  * 2nd innings done (target set) -> the fold's computed result + finish.
  Widget _endPanel({
    required Map<String, dynamic> s,
    required Map<String, dynamic> innings,
    required List<Map<String, dynamic>> squad,
    required Map<String, String> teamNames,
    required String battingTeam,
    required String bowlingTeam,
    required int? target,
    required bool matchDone,
  }) {
    final runs = (s['runs'] as num?)?.toInt() ?? 0;
    final wkts = (s['wickets'] as num?)?.toInt() ?? 0;
    final battingName = teamNames[battingTeam] ?? 'Batting side';

    Widget wrap(List<Widget> children) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );

    if (matchDone) {
      return wrap([
        const Text('Match complete',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_resultLine(s['result'], teamNames)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.push(Routes.viewMatch(widget.matchId)),
          child: const Text('View scorecard'),
        ),
      ]);
    }

    if (target == null) {
      // 1st innings done -> break, then start the chase.
      // SCOR-1: the break is real match state, not just a console panel -
      // write it once so viewers/lists show 'innings break' instead of 'live'.
      if (!_breakMarked) {
        _breakMarked = true;
        _repo.markInningsBreak(widget.matchId).then((_) {
          if (mounted) ref.invalidate(matchProvider(widget.matchId));
        }).catchError((_) {/* non-fatal: purely presentational state */});
      }
      final chaseTarget = runs + 1;
      return wrap([
        const Text('Innings break',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('$battingName finished on $runs/$wkts.'),
        const SizedBox(height: 4),
        Text('Target: $chaseTarget   (they must chase $chaseTarget to win)',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _startSecondInnings(
                    chaseBatting: bowlingTeam, // sides swap for the 2nd innings
                    chaseBowling: battingTeam,
                    squad: squad,
                    teamNames: teamNames,
                    target: chaseTarget,
                  ),
          child: const Text('Start 2nd innings'),
        ),
      ]);
    }

    // 2nd innings done -> finish with the fold's computed result.
    return wrap([
      const Text('Match over',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(_resultLine(s['result'], teamNames),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _busy ? null : () => _finishMatch(s['result'], teamNames),
        child: const Text('Finish match & view scorecard'),
      ),
    ]);
  }

  /// Human result from the fold's `result` jsonb (win_by_wickets/runs/tie).
  String _resultLine(dynamic result, Map<String, String> teamNames) {
    if (result is! Map) return 'Result pending.';
    final type = result['result_type'] as String?;
    final winner = teamNames[result['winner_team_id']] ?? 'The winning side';
    switch (type) {
      case 'win_by_wickets':
        final w = (result['margin_wickets'] as num?)?.toInt();
        final b = (result['balls_remaining'] as num?)?.toInt();
        return '$winner won by $w wicket${w == 1 ? '' : 's'}'
            '${b != null ? ' ($b ball${b == 1 ? '' : 's'} left)' : ''}.';
      case 'win_by_runs':
        final r = (result['margin_runs'] as num?)?.toInt();
        return '$winner won by $r run${r == 1 ? '' : 's'}.';
      case 'tie':
        return 'Match tied.';
      default:
        return 'Match complete.';
    }
  }

  Future<void> _finishMatch(dynamic result, Map<String, String> teamNames) async {
    if (result is! Map) return;
    setState(() => _busy = true);
    try {
      final type = result['result_type'] as String? ?? 'no_result';
      await _repo.setResult(
        matchId: widget.matchId,
        resultType: type,
        winnerTeamId: result['winner_team_id'] as String?,
        note: _resultLine(result, teamNames), // the full human result sentence
      );
      ref.invalidate(matchProvider(widget.matchId));
      ref.invalidate(myMatchesProvider); // history must show the result
      // If this was a TOURNAMENT fixture, its result changes the standings and
      // is what unlocks generating the playoffs. The organizer's manage screen
      // and the public tournament page both read tournamentOverviewProvider,
      // and nothing here refreshed it - so the organizer finished the last
      // group game and the Generate playoffs button stayed disabled forever
      // (re-review 2026-07-07, the same stale-provider class as the squad
      // handoff).
      final tid = await _tournamentIdOf(widget.matchId);
      if (tid != null) ref.invalidate(tournamentOverviewProvider(tid));
      if (mounted) context.pushReplacement(Routes.viewMatch(widget.matchId));
    } catch (e) {
      _toast(humanError(e, fallback: 'Could not close the innings.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The tournament this match belongs to, or null for a casual game.
  Future<String?> _tournamentIdOf(String matchId) async {
    try {
      final row = await ref
          .read(supabaseClientProvider)
          .from('tournament_matches')
          .select('tournament_id')
          .eq('match_id', matchId)
          .maybeSingle();
      return row?['tournament_id'] as String?;
    } catch (_) {
      return null; // never let a refresh lookup break finishing a match
    }
  }

  Future<void> _startSecondInnings({
    required String chaseBatting,
    required String chaseBowling,
    required List<Map<String, dynamic>> squad,
    required Map<String, String> teamNames,
    required int target,
  }) async {
    final openers = await _pickTwoOpeners(chaseBatting, squad, teamNames);
    if (openers == null) return;
    setState(() => _busy = true);
    try {
      await _repo.startInnings(
        matchId: widget.matchId,
        inningsNumber: 2,
        battingTeam: chaseBatting,
        bowlingTeam: chaseBowling,
        openingStriker: openers.$1,
        openingNonStriker: openers.$2,
        target: target,
      );
      ref.invalidate(currentInningsProvider(widget.matchId));
      ref.invalidate(matchInningsListProvider(widget.matchId));
      if (mounted) {
        setState(() {
          _bowlerId = null;
          _lastOverBowlerId = null; // fresh innings, fresh over sequence
        });
      }
    } catch (e) {
      _toast(humanError(e, fallback: 'Could not start the next innings.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Bottom sheet: pick striker + non-striker for the chasing side.
  Future<(String, String)?> _pickTwoOpeners(
    String battingTeam,
    List<Map<String, dynamic>> squad,
    Map<String, String> teamNames,
  ) {
    final batters = [
      for (final m in squad)
        if (m['team_id'] == battingTeam) m,
    ];
    String? striker;
    String? nonStriker;
    return showModalBottomSheet<(String, String)?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          // SCOR-14: the pickers are mutually exclusive - choosing one batter
          // removes them from the other dropdown instead of failing at submit.
          Widget picker(String label, String? value, String? exclude,
                  ValueChanged<String?> on) =>
              Row(children: [
                SizedBox(width: 110, child: Text(label)),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: value,
                    hint: const Text('Choose'),
                    items: [
                      for (final b in batters)
                        if (b['team_member_id'] != exclude)
                          DropdownMenuItem(
                            value: b['team_member_id'] as String,
                            child: Text(memberName(
                                b['team_members'] as Map<String, dynamic>)),
                          ),
                    ],
                    onChanged: on,
                  ),
                ),
              ]);
          final ready =
              striker != null && nonStriker != null && striker != nonStriker;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${teamNames[battingTeam] ?? 'Chasing side'} - opening pair',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  picker('Striker', striker, nonStriker,
                      (v) => setSheet(() => striker = v)),
                  picker('Non-striker', nonStriker, striker,
                      (v) => setSheet(() => nonStriker = v)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: ready
                        ? () => Navigator.pop(context, (striker!, nonStriker!))
                        : null,
                    child: const Text('Start chase'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pad(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) {
    final lastSeq = (s['last_seq'] as num?)?.toInt();
    Widget runBtn(int n, {bool boundary = false}) => _Btn(
          label: '$n',
          color: boundary ? const Color(0xFFE1F5EE) : null,
          onTap: () => _record(inningsId, bpo, runs: n, lastSeq: lastSeq),
        );
    // scrolls when the screen is short (SE-class phones, split view)
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [runBtn(0), runBtn(1), runBtn(2)]),
          Row(children: [runBtn(3), runBtn(4, boundary: true), runBtn(6, boundary: true)]),
          Row(
            children: [
              _Btn(
                  label: 'Wd',
                  onTap: () =>
                      _record(inningsId, bpo, wides: 1, lastSeq: lastSeq)),
              _Btn(
                  label: 'Nb',
                  onTap: () =>
                      _record(inningsId, bpo, noBall: 1, lastSeq: lastSeq)),
              _Btn(
                  label: 'B',
                  onTap: () =>
                      _record(inningsId, bpo, byes: 1, lastSeq: lastSeq)),
              _Btn(
                  label: 'Lb',
                  onTap: () =>
                      _record(inningsId, bpo, legByes: 1, lastSeq: lastSeq)),
            ],
          ),
          Row(
            children: [
              _Btn(
                  label: 'Extras',
                  onTap: () => _extras(inningsId, bpo, lastSeq: lastSeq)),
              _Btn(
                label: 'WICKET',
                color: const Color(0xFFFFE5E2),
                onTap: () => _wicket(
                    inningsId, bpo, squad, battingTeam, bowlingTeam, names, s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// SCOR-16: retirement sheet - who leaves, hurt vs out, who comes in.
  Future<void> _retire(
    String inningsId,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) async {
    final strikerId = s['striker_id'] as String?;
    final nonStrikerId = s['non_striker_id'] as String?;
    final gone = <String>{
      for (final w in (s['fall_of_wickets'] as List? ?? const []))
        if ((w as Map)['dismissed_player_id'] != null)
          w['dismissed_player_id'] as String,
      // retired-hurt batters cannot return in v1 either
      for (final b in (s['batting'] as List? ?? const []))
        if ((b as Map)['batter_id'] != null &&
            b['batter_id'] != strikerId &&
            b['batter_id'] != nonStrikerId)
          b['batter_id'] as String,
    };
    final availableIncoming = [
      for (final m in squad)
        if (m['team_id'] == battingTeam) m['team_member_id'] as String,
    ]
        .where((id) =>
            id != strikerId && id != nonStrikerId && !gone.contains(id))
        .toList();

    String who = 'striker';
    bool out = false;
    String? incoming;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Retire batter',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                    label: Text(names[strikerId] ?? 'Striker'),
                    selected: who == 'striker',
                    onSelected: (_) => setSheet(() => who = 'striker'),
                  ),
                  ChoiceChip(
                    label: Text(names[nonStrikerId] ?? 'Non-striker'),
                    selected: who == 'non_striker',
                    onSelected: (_) => setSheet(() => who = 'non_striker'),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Retired out'),
                  subtitle: const Text(
                      'Off: retired hurt (not out, no wicket falls)'),
                  value: out,
                  onChanged: (v) => setSheet(() => out = v),
                ),
                const Text('Incoming batter'),
                DropdownButton<String>(
                  isExpanded: true,
                  value: incoming,
                  hint: const Text('Choose'),
                  items: [
                    for (final id in availableIncoming)
                      DropdownMenuItem(value: id, child: Text(names[id] ?? '-')),
                  ],
                  onChanged: (v) => setSheet(() => incoming = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: incoming == null
                      ? null
                      : () => Navigator.pop(context, true),
                  child: const Text('Retire'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok ?? false) {
      setState(() => _busy = true);
      try {
        await _repo.retireBatter(
          inningsId: inningsId,
          batterId: (who == 'striker' ? strikerId : nonStrikerId)!,
          out: out,
          incomingBatterId: incoming,
        );
        ref.invalidate(inningsStateProvider(inningsId));
      } catch (e) {
        _toast(humanError(e, fallback: 'Could not retire that batter.'));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  /// SCOR-15: the bowler picker shows each bowler's live figures and blocks
  /// the two illegal picks - the previous over's bowler and anyone at the
  /// match's per-bowler over quota.
  /// Undo / swap-strike / retire: actions that apply BETWEEN balls, so they must
  /// stay live even with no bowler selected and while the pad is disabled.
  Widget _betweenBallRow(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          _Btn(
            label: 'Undo',
            onTap: _undoBusy ? null : () => _undo(inningsId, bpo),
          ),
          _Btn(
            label: 'Swap strike',
            onTap: _undoBusy
                ? null
                : () async {
                    try {
                      await _repo.swapStrike(inningsId);
                      ref.invalidate(inningsStateProvider(inningsId));
                    } catch (e) {
                      _toast(humanError(e, fallback: 'Could not swap.'));
                    }
                  },
          ),
          _Btn(
            label: 'Retire',
            onTap: _undoBusy
                ? null
                : () => _retire(inningsId, squad, battingTeam, names, s),
          ),
        ],
      ),
    );
  }

  /// Undo needs its own in-flight guard: without one a double tap deletes TWO
  /// deliveries and the scorer has no way to tell (penetration review
  /// 2026-07-07).
  ///
  /// It also has to put the BOWLER back. When the last ball of an over is
  /// undone, the over is open again - and it is still the previous bowler's
  /// over. Leaving _bowlerId null forces the scorer to pick someone, and the
  /// re-recorded ball is then credited to a bowler who never bowled it. So we
  /// restore _lastOverBowlerId, which _afterBall already stashed when the over
  /// completed.
  Future<void> _undo(String inningsId, int bpo) async {
    if (_undoBusy) return;
    setState(() => _undoBusy = true);
    try {
      await _repo.undoLastBall(inningsId);
      ref.invalidate(inningsStateProvider(inningsId));
      final after = await ref.read(inningsStateProvider(inningsId).future);
      final legalAfter = (after['legal_balls'] as num?)?.toInt() ?? 0;
      // mid-over again: whoever was bowling that over resumes it
      if (legalAfter % bpo != 0 && _bowlerId == null && _lastOverBowlerId != null) {
        if (mounted) {
          setState(() {
            _bowlerId = _lastOverBowlerId;
            _lastOverBowlerId = null;
          });
        }
      }
    } catch (e) {
      _toast(humanError(e, fallback: 'Could not undo.'));
    } finally {
      if (mounted) setState(() => _undoBusy = false);
    }
  }

  Future<void> _pickBowler(
    List<Map<String, dynamic>> squad,
    String bowlingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
    int bpo,
  ) async {
    final bowlers = [
      for (final m in squad)
        if (m['team_id'] == bowlingTeam) m['team_member_id'] as String,
    ];
    final figures = <String, Map<String, dynamic>>{
      for (final b in (s['bowling'] as List? ?? const []))
        (b as Map)['bowler_id'] as String: b.cast<String, dynamic>(),
    };
    final rules =
        ref.read(matchProvider(widget.matchId)).value?['rules'] as Map?;
    final capOvers = (rules?['max_overs_per_bowler'] as num?)?.toInt();

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Select bowler'),
              subtitle:
                  capOvers != null ? Text('Max $capOvers overs each') : null,
            ),
            for (final id in bowlers)
              Builder(builder: (context) {
                final f = figures[id];
                final legalBalls = (f?['legal_balls'] as num?)?.toInt() ?? 0;
                final overs = f?['overs'] ?? '0.0';
                final runsC = (f?['runs_conceded'] as num?)?.toInt() ?? 0;
                final wkts = (f?['wickets'] as num?)?.toInt() ?? 0;
                final atCap =
                    capOvers != null && legalBalls >= capOvers * bpo;
                final lastOver = id == _lastOverBowlerId;
                final blocked = atCap || lastOver;
                return ListTile(
                  enabled: !blocked,
                  title: Text(names[id] ?? '-'),
                  subtitle: Text(
                    f == null
                        ? 'Yet to bowl'
                        : '$overs ov - $runsC runs - $wkts wkt${wkts == 1 ? '' : 's'}',
                  ),
                  trailing: atCap
                      ? const Text('At over limit')
                      : lastOver
                          ? const Text('Bowled last over')
                          : null,
                  onTap: blocked ? null : () => Navigator.pop(context, id),
                );
              }),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _bowlerId = picked);
  }

  /// The pad's internal keys are plural ('byes'/'leg_byes') because they double
  /// as extra-type keys, but public.noball_secondary_kind is
  /// ('off_bat','bye','leg_bye'). Sending the plural form made every
  /// no-ball-that-went-for-byes a hard 400 (penetration review 2026-07-07).
  static String? _nbKindEnum(String uiKey) => switch (uiKey) {
        'off_bat' => 'off_bat',
        'byes' => 'bye',
        'leg_byes' => 'leg_bye',
        _ => null,
      };

  // 'retired_out' / 'timed_out' are deliberately ABSENT: a retirement is an
  // event BETWEEN balls, not a delivery. Recording one here consumed a ball,
  // advanced the over, charged the bowler, and dismissed the STRIKER rather
  // than the batter the scorer named. Use the Retire action instead -
  // record_ball now rejects these types and a CHECK constraint backs it.
  static const _allWicketTypes = [
    'bowled', 'caught', 'lbw', 'run_out', 'stumped', 'hit_wicket',
    'obstructing', 'hit_ball_twice',
  ];
  // Only these are legal on a free hit (mirrors record_ball's guard).
  static const _freeHitWicketTypes = ['run_out', 'obstructing', 'hit_ball_twice'];
  // A wicket can fall off a wide or a no-ball, and the console used to have no
  // way to say so - every dismissal it produced was a legal delivery. A
  // stumping off a wide is a T20 staple; a run-out off a no-ball is routine.
  // Scored as an ordinary dismissal they cost the innings the extra run AND
  // burn a legal ball, so the over ends a delivery early and every over after
  // it is misattributed (whole-system review #2, 2026-07-28).
  //
  // These mirror record_ball's guards exactly. A no-ball allows the same set as
  // a free hit, for the same reason: the bowler cannot be credited.
  static const _wideWicketTypes = [
    'stumped', 'run_out', 'hit_wicket', 'obstructing',
  ];
  static const _noBallWicketTypes = _freeHitWicketTypes;

  /// A free hit can itself be a wide, and then BOTH guards bind - so intersect
  /// rather than picking one.
  static List<String> _typesFor(String delivery, bool freeHit) {
    final base = switch (delivery) {
      'wide' => _wideWicketTypes,
      'no_ball' => _noBallWicketTypes,
      _ => _allWicketTypes,
    };
    if (!freeHit) return base;
    return [for (final t in base) if (_freeHitWicketTypes.contains(t)) t];
  }

  static bool _needsWhoOut(String t) =>
      t == 'run_out' || t == 'obstructing' || t == 'retired_out';
  static bool _needsFielder(String t) =>
      t == 'caught' || t == 'stumped' || t == 'run_out';
  static bool _needsCrossedRuns(String t) => t == 'run_out' || t == 'obstructing';

  String _wicketLabel(String t) => switch (t) {
        'bowled' => 'Bowled',
        'caught' => 'Caught',
        'lbw' => 'LBW',
        'run_out' => 'Run out',
        'stumped' => 'Stumped',
        'hit_wicket' => 'Hit wicket',
        'retired_out' => 'Retired out',
        'obstructing' => 'Obstructing',
        'timed_out' => 'Timed out',
        'hit_ball_twice' => 'Hit the ball twice',
        _ => t,
      };

  Future<void> _wicket(
    String inningsId,
    int bpo,
    List<Map<String, dynamic>> squad,
    String battingTeam,
    String bowlingTeam,
    Map<String, String> names,
    Map<String, dynamic> s,
  ) async {
    final strikerId = s['striker_id'] as String?;
    final nonStrikerId = s['non_striker_id'] as String?;
    final freeHit = s['free_hit_active'] == true;
    final wktsRem = (s['wickets_remaining'] as num?)?.toInt() ?? 99;
    final isLastWicket = wktsRem <= 1;

    // batters already dismissed (from the fold's fall of wickets)
    final gone = <String>{
      for (final w in (s['fall_of_wickets'] as List? ?? const []))
        if ((w as Map)['dismissed_player_id'] != null)
          w['dismissed_player_id'] as String,
    };
    final availableIncoming = [
      for (final m in squad)
        if (m['team_id'] == battingTeam)
          m['team_member_id'] as String,
    ].where((id) =>
        id != strikerId && id != nonStrikerId && !gone.contains(id)).toList();
    final fielders = [
      for (final m in squad)
        if (m['team_id'] == bowlingTeam) m['team_member_id'] as String,
    ];

    String delivery = 'legal';
    String type = _typesFor(delivery, freeHit).first;
    String whoOut = 'striker';
    String? fielder;
    bool crossed = false;
    int runs = 0;
    String? incoming;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final needIncoming = !isLastWicket;
          final canRecord = !needIncoming || incoming != null;
          final types = _typesFor(delivery, freeHit);
          // A wide charges its own run; a no-ball its own penalty. The counter
          // means something different in each case, so say which.
          final runsLabel = switch (delivery) {
            'wide' => 'Extra runs run',
            'no_ball' => 'Runs off the bat',
            _ => 'Runs completed',
          };
          final showRuns = _needsCrossedRuns(type) || delivery != 'legal';
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
                    if (freeHit)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Free hit - only a run-out counts',
                            style: TextStyle(color: Color(0xFFB26A00))),
                      ),
                    const Text('The delivery was'),
                    Wrap(spacing: 8, children: [
                      for (final (d, l) in const [
                        ('legal', 'Legal ball'),
                        ('wide', 'Wide'),
                        ('no_ball', 'No-ball'),
                      ])
                        ChoiceChip(
                          label: Text(l),
                          selected: delivery == d,
                          onSelected: (_) => setSheet(() {
                            delivery = d;
                            // The allowed dismissals shrink with the delivery -
                            // keep the selection legal rather than letting a
                            // stale "Bowled" ride along into a server error.
                            final allowed = _typesFor(delivery, freeHit);
                            if (!allowed.contains(type)) type = allowed.first;
                          }),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    const Text('How out?'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in types)
                          ChoiceChip(
                            label: Text(_wicketLabel(t)),
                            selected: type == t,
                            onSelected: (_) => setSheet(() => type = t),
                          ),
                      ],
                    ),
                    if (_needsWhoOut(type)) ...[
                      const SizedBox(height: 12),
                      const Text('Who is out?'),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                          label: Text(names[strikerId] ?? 'Striker'),
                          selected: whoOut == 'striker',
                          onSelected: (_) => setSheet(() => whoOut = 'striker'),
                        ),
                        ChoiceChip(
                          label: Text(names[nonStrikerId] ?? 'Non-striker'),
                          selected: whoOut == 'non_striker',
                          onSelected: (_) =>
                              setSheet(() => whoOut = 'non_striker'),
                        ),
                      ]),
                    ],
                    if (showRuns) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Text(runsLabel),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed:
                              runs > 0 ? () => setSheet(() => runs--) : null,
                        ),
                        Text('$runs', style: const TextStyle(fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setSheet(() => runs++),
                        ),
                      ]),
                      if (_needsCrossedRuns(type))
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Batters had crossed'),
                          value: crossed,
                          onChanged: (v) => setSheet(() => crossed = v),
                        ),
                    ],
                    if (_needsFielder(type)) ...[
                      const SizedBox(height: 12),
                      const Text('Fielder'),
                      DropdownButton<String>(
                        isExpanded: true,
                        value: fielder,
                        hint: const Text('Choose (optional)'),
                        items: [
                          for (final id in fielders)
                            DropdownMenuItem(
                                value: id, child: Text(names[id] ?? '-')),
                        ],
                        onChanged: (v) => setSheet(() => fielder = v),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(isLastWicket
                        ? 'Incoming batter (last wicket - none needed)'
                        : 'Incoming batter'),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: incoming,
                      hint: const Text('Choose'),
                      items: [
                        for (final id in availableIncoming)
                          DropdownMenuItem(
                              value: id, child: Text(names[id] ?? '-')),
                      ],
                      onChanged: (v) => setSheet(() => incoming = v),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: canRecord
                          ? () => Navigator.pop(context, true)
                          : null,
                      child: const Text('Record wicket'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (ok ?? false) {
      final dismissedId = _needsWhoOut(type) && whoOut == 'non_striker'
          ? nonStrikerId
          : strikerId;
      // A wide's runs are extras on top of the wide itself; a no-ball's are off
      // the bat on top of the penalty; a legal ball's are only meaningful for
      // the run-out family. Sending any of these as a bare legal delivery is
      // what made a stumping-off-a-wide unrecordable.
      final offBat = switch (delivery) {
        'wide' => 0,
        'no_ball' => runs,
        _ => _needsCrossedRuns(type) ? runs : 0,
      };
      await _record(
        inningsId,
        bpo,
        runs: offBat,
        wides: delivery == 'wide' ? 1 + runs : 0,
        noBall: delivery == 'no_ball' ? 1 : 0,
        noballSecondaryKind:
            delivery == 'no_ball' && runs > 0 ? _nbKindEnum('off_bat') : null,
        wicketType: type,
        dismissedId: dismissedId,
        incomingId: incoming,
        fielderId: _needsFielder(type) ? fielder : null,
        crossed: _needsCrossedRuns(type) ? crossed : null,
        lastSeq: (s['last_seq'] as num?)?.toInt(),
      );
    }
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.label, required this.onTap, this.color});

  final String label;
  /// Nullable so an action can be genuinely DISABLED (greyed, not tappable)
  /// while its own request is in flight - Undo needs this to stop a double tap
  /// deleting two deliveries.
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      ),
    );
  }
}
