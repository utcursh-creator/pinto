import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Write operations for match setup + ball-by-ball scoring.
class MatchRepository {
  MatchRepository(this._c);

  final SupabaseClient _c;

  Future<String> createMatch({
    required String teamA,
    required String teamB,
    required int overs,
    String? venue,
    String? ballType,
  }) async {
    final params = <String, dynamic>{
      '_team_a': teamA,
      '_team_b': teamB,
      '_overs': overs,
      // SCOR-15: every app-created match carries the bowler quota rule
      // (ceil(overs/5): T20 -> 4). record_ball enforces it at over start.
      '_rules': {'max_overs_per_bowler': (overs + 4) ~/ 5},
    };
    if (venue != null && venue.isNotEmpty) params['_venue'] = venue;
    if (ballType != null) params['_ball_type'] = ballType;
    final id = await _c.rpc('create_match', params: params);
    return id as String;
  }

  Future<void> addSquadMember({
    required String matchId,
    required String teamId,
    required String teamMemberId,
    int? battingOrder,
    bool isCaptain = false,
    bool isKeeper = false,
  }) =>
      _c.rpc('add_squad_member', params: {
        '_match_id': matchId,
        '_team_id': teamId,
        '_team_member_id': teamMemberId,
        '_batting_order': ?battingOrder,
        '_is_captain': isCaptain,
        '_is_keeper': isKeeper,
      });

  /// Adds a guest player to a participating team during setup (scorer-gated).
  /// Returns the new team_member id. (SCOR-11)
  Future<String> addMatchGuest({
    required String matchId,
    required String teamId,
    required String guestName,
  }) async {
    final id = await _c.rpc('add_match_guest', params: {
      '_match_id': matchId,
      '_team_id': teamId,
      '_guest_name': guestName,
    });
    return id as String;
  }

  /// Records the toss. Goes through set_toss, NOT a direct table UPDATE:
  /// UPDATE on matches is no longer granted to clients, because a blanket grant
  /// made every guard in set_match_result and update_match_schedule decorative
  /// (a scorer could PATCH result/status/team ids straight onto the row and
  /// fabricate a public record - penetration review 2026-07-07). The RPC also
  /// validates that the toss winner is actually one of the two teams playing.
  Future<void> setToss({
    required String matchId,
    required String winnerTeamId,
    required String decision, // 'bat' | 'bowl'
  }) =>
      _c.rpc('set_toss', params: {
        '_match_id': matchId,
        '_winner_team_id': winnerTeamId,
        '_decision': decision,
      });

  Future<String> startInnings({
    required String matchId,
    required int inningsNumber,
    required String battingTeam,
    required String bowlingTeam,
    required String openingStriker,
    required String openingNonStriker,
    int? target,
  }) async {
    final params = <String, dynamic>{
      '_match_id': matchId,
      '_innings_number': inningsNumber,
      '_batting_team': battingTeam,
      '_bowling_team': bowlingTeam,
      '_opening_striker': openingStriker,
      '_opening_non_striker': openingNonStriker,
    };
    if (target != null) params['_target'] = target;
    final id = await _c.rpc('start_innings', params: params);
    return id as String;
  }

  /// Records a delivery; returns its id + whether to prompt the wagon sheet.
  /// [expectedLastSeq] is the fold's last_seq the scorer acted on (SCOR-24) -
  /// the server rejects the append if another device changed the innings.
  Future<({String? deliveryId, bool wagonApplicable})> recordBall({
    required String inningsId,
    required String bowlerId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    bool isOverthrow = false,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
    bool? crossed,
    int? expectedLastSeq,
  }) async {
    final params = <String, dynamic>{
      '_innings_id': inningsId,
      '_bowler_id': bowlerId,
      '_runs_off_bat': runsOffBat,
      '_extra_wides': wides,
      '_extra_no_ball_penalty': noBallPenalty,
      '_extra_byes': byes,
      '_extra_leg_byes': legByes,
      '_extra_penalty': penalty,
      '_is_overthrow': isOverthrow,
    };
    if (noballSecondaryKind != null) {
      params['_noball_secondary_kind'] = noballSecondaryKind;
    }
    if (wicketType != null) params['_wicket_type'] = wicketType;
    if (dismissedPlayerId != null) params['_dismissed_player_id'] = dismissedPlayerId;
    if (incomingBatterId != null) params['_incoming_batter_id'] = incomingBatterId;
    if (fielderId != null) params['_fielder_id'] = fielderId;
    if (crossed != null) params['_crossed'] = crossed;
    if (expectedLastSeq != null) params['_expected_last_seq'] = expectedLastSeq;
    final res = await _c.rpc('record_ball', params: params).single();
    return (
      deliveryId: res['delivery_id'] as String?,
      wagonApplicable: (res['wagon_applicable'] as bool?) ?? false,
    );
  }

  /// SCOR-16: retirement between balls (hurt keeps the batter not out; out
  /// counts as a wicket). A non-ball event row - no ball is consumed.
  Future<void> retireBatter({
    required String inningsId,
    required String batterId,
    required bool out,
    String? incomingBatterId,
  }) =>
      _c.rpc('retire_batter', params: {
        '_innings_id': inningsId,
        '_retiring_batter_id': batterId,
        '_out': out,
        '_incoming_batter_id': ?incomingBatterId,
      });

  /// SCOR-16: manual strike correction (umpire-directed end change).
  Future<void> swapStrike(String inningsId) =>
      _c.rpc('swap_strike', params: {'_innings_id': inningsId});

  /// SCOR-1: record the first-innings close on the match itself so viewers
  /// and lists see 'innings break' instead of a frozen 'live'.
  Future<void> markInningsBreak(String matchId) =>
      _c.rpc('mark_innings_break', params: {'_match_id': matchId});

  /// TOUR-4 / MTCH-7: set (or clear) a match's date + ground.
  Future<void> updateMatchSchedule({
    required String matchId,
    DateTime? scheduledAt,
    String? venue,
  }) =>
      _c.rpc('update_match_schedule', params: {
        '_match_id': matchId,
        '_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        '_venue': venue,
      });

  /// Attaches a wagon-wheel shot (normalized x/y in [0,1] + zone 1-8) to a ball.
  Future<void> setDeliveryWagon({
    required String deliveryId,
    required double x,
    required double y,
    required int zone,
  }) =>
      _c.rpc('set_delivery_wagon', params: {
        '_delivery_id': deliveryId,
        '_wagon_x': x,
        '_wagon_y': y,
        '_wagon_zone': zone,
      });

  Future<void> undoLastBall(String inningsId) =>
      _c.rpc('undo_last_ball', params: {'_innings_id': inningsId});

  /// Corrections. edit_ball is a FULL overwrite of the delivery's scoring
  /// columns (omitted params reset to 0/null), so callers pass the complete
  /// intended state of the ball, not a patch.
  Future<void> editBall({
    required String deliveryId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
    // edit_ball is COALESCE-patch shaped: omitting a field KEEPS it. So a null
    // wicketType cannot mean "remove the wicket" - the RPC has explicit
    // _clear_wicket / _clear_wagon flags for that, and nothing was sending them,
    // which made turning "Wicket" off in the editor a silent no-op
    // (whole-system review #2).
    bool clearWicket = false,
    bool clearWagon = false,
  }) {
    final params = <String, dynamic>{
      '_delivery_id': deliveryId,
      if (clearWicket) '_clear_wicket': true,
      if (clearWagon) '_clear_wagon': true,
      '_runs_off_bat': runsOffBat,
      '_extra_wides': wides,
      '_extra_no_ball_penalty': noBallPenalty,
      '_extra_byes': byes,
      '_extra_leg_byes': legByes,
      '_extra_penalty': penalty,
    };
    if (noballSecondaryKind != null) {
      params['_noball_secondary_kind'] = noballSecondaryKind;
    }
    if (wicketType != null) params['_wicket_type'] = wicketType;
    if (dismissedPlayerId != null) params['_dismissed_player_id'] = dismissedPlayerId;
    if (incomingBatterId != null) params['_incoming_batter_id'] = incomingBatterId;
    if (fielderId != null) params['_fielder_id'] = fielderId;
    return _c.rpc('edit_ball', params: params);
  }

  /// Inserts a missed delivery after [afterSeq]; the server shifts later balls
  /// and re-stamps strike. Returns the new delivery id.
  Future<String> insertBall({
    required String inningsId,
    required int afterSeq,
    required String bowlerId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    int penalty = 0,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
  }) async {
    final params = <String, dynamic>{
      '_innings_id': inningsId,
      '_after_seq': afterSeq,
      '_bowler_id': bowlerId,
      '_runs_off_bat': runsOffBat,
      '_extra_wides': wides,
      '_extra_no_ball_penalty': noBallPenalty,
      '_extra_byes': byes,
      '_extra_leg_byes': legByes,
      '_extra_penalty': penalty,
    };
    if (noballSecondaryKind != null) {
      params['_noball_secondary_kind'] = noballSecondaryKind;
    }
    if (wicketType != null) params['_wicket_type'] = wicketType;
    if (dismissedPlayerId != null) params['_dismissed_player_id'] = dismissedPlayerId;
    if (incomingBatterId != null) params['_incoming_batter_id'] = incomingBatterId;
    if (fielderId != null) params['_fielder_id'] = fielderId;
    final id = await _c.rpc('insert_ball', params: params);
    return id as String;
  }

  Future<void> deleteBall(String deliveryId) =>
      _c.rpc('delete_ball', params: {'_delivery_id': deliveryId});

  /// Hand scoring to another registered member of either team.
  Future<void> transferScorer({
    required String matchId,
    required String newScorerId,
  }) =>
      _c.rpc('transfer_scorer', params: {
        '_match_id': matchId,
        '_new_scorer_id': newScorerId,
      });

  Future<void> setResult({
    required String matchId,
    required String resultType,
    String? winnerTeamId,
    String? note,
  }) {
    final params = <String, dynamic>{
      '_match_id': matchId,
      '_result_type': resultType,
    };
    if (winnerTeamId != null) params['_winner_team_id'] = winnerTeamId;
    if (note != null && note.isNotEmpty) params['_note'] = note;
    return _c.rpc('set_match_result', params: params);
  }

  /// Owner-only hard delete of a match (cascades innings/deliveries/squad).
  /// Used from the Matches list (MTCH-2). Blocked for tournament matches.
  Future<void> deleteMatch(String matchId) =>
      _c.rpc('delete_match', params: {'_match_id': matchId});
}

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => MatchRepository(ref.watch(supabaseClientProvider)),
);
