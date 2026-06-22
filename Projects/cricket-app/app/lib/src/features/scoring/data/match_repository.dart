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
  }) async {
    final params = <String, dynamic>{
      '_team_a': teamA,
      '_team_b': teamB,
      '_overs': overs,
    };
    if (venue != null && venue.isNotEmpty) params['_venue'] = venue;
    final id = await _c.rpc('create_match', params: params);
    return id as String;
  }

  Future<void> addSquadMember({
    required String matchId,
    required String teamId,
    required String teamMemberId,
  }) =>
      _c.rpc('add_squad_member', params: {
        '_match_id': matchId,
        '_team_id': teamId,
        '_team_member_id': teamMemberId,
      });

  Future<void> setToss({
    required String matchId,
    required String winnerTeamId,
    required String decision, // 'bat' | 'bowl'
  }) =>
      _c
          .from('matches')
          .update({'toss_winner_id': winnerTeamId, 'toss_decision': decision})
          .eq('id', matchId);

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
  Future<({String? deliveryId, bool wagonApplicable})> recordBall({
    required String inningsId,
    required String bowlerId,
    int runsOffBat = 0,
    int wides = 0,
    int noBallPenalty = 0,
    int byes = 0,
    int legByes = 0,
    String? noballSecondaryKind,
    String? wicketType,
    String? dismissedPlayerId,
    String? incomingBatterId,
    String? fielderId,
    bool? crossed,
  }) async {
    final params = <String, dynamic>{
      '_innings_id': inningsId,
      '_bowler_id': bowlerId,
      '_runs_off_bat': runsOffBat,
      '_extra_wides': wides,
      '_extra_no_ball_penalty': noBallPenalty,
      '_extra_byes': byes,
      '_extra_leg_byes': legByes,
    };
    if (noballSecondaryKind != null) {
      params['_noball_secondary_kind'] = noballSecondaryKind;
    }
    if (wicketType != null) params['_wicket_type'] = wicketType;
    if (dismissedPlayerId != null) params['_dismissed_player_id'] = dismissedPlayerId;
    if (incomingBatterId != null) params['_incoming_batter_id'] = incomingBatterId;
    if (fielderId != null) params['_fielder_id'] = fielderId;
    if (crossed != null) params['_crossed'] = crossed;
    final res = await _c.rpc('record_ball', params: params).single();
    return (
      deliveryId: res['delivery_id'] as String?,
      wagonApplicable: (res['wagon_applicable'] as bool?) ?? false,
    );
  }

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
  }) {
    final params = <String, dynamic>{
      '_match_id': matchId,
      '_result_type': resultType,
    };
    if (winnerTeamId != null) params['_winner_team_id'] = winnerTeamId;
    return _c.rpc('set_match_result', params: params);
  }
}

final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => MatchRepository(ref.watch(supabaseClientProvider)),
);
