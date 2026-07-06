import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/supabase/supabase_providers.dart';

/// Name of a squad/roster member row shaped {guest_name, profiles:{display_name}}.
String memberName(Map<String, dynamic> m) {
  final guest = m['guest_name'] as String?;
  if (guest != null && guest.isNotEmpty) return guest;
  final p = m['profiles'] as Map<String, dynamic>?;
  return (p?['display_name'] as String?) ?? 'Player';
}

/// All teams (for the opponent picker).
final allTeamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final c = ref.watch(supabaseClientProvider);
  final rows = await c.from('teams').select('id, name, city').order('name');
  return List<Map<String, dynamic>>.from(rows as List);
});

/// A team's members (for squad selection).
final teamMembersProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, teamId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('team_members')
          .select('id, profile_id, guest_name, profiles(display_name)')
          .eq('team_id', teamId);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// A match row.
final matchProvider = FutureProvider.family<Map<String, dynamic>?, String>((
  ref,
  matchId,
) async {
  final c = ref.watch(supabaseClientProvider);
  return c.from('matches').select().eq('id', matchId).maybeSingle();
});

/// A match's squad, with each member's name + which team they're on.
final matchSquadProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('match_squad')
          .select(
            'team_id, team_member_id, batting_order, is_captain, is_keeper, '
            'team_members(id, guest_name, profiles(display_name))',
          )
          .eq('match_id', matchId)
          // SCOR-13: squad lists follow the declared batting order
          .order('batting_order', ascending: true, nullsFirst: false);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// The latest innings of a match (to resume scoring / view).
final currentInningsProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      return c
          .from('innings')
          .select('id, innings_number, batting_team_id, bowling_team_id, status, target')
          .eq('match_id', matchId)
          .order('innings_number', ascending: false)
          .limit(1)
          .maybeSingle();
    });

/// All innings of a match, oldest first (for the viewer's innings switcher).
final matchInningsListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('innings')
          .select(
            'id, innings_number, batting_team_id, bowling_team_id, status, target',
          )
          .eq('match_id', matchId)
          .order('innings_number');
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// Map of {teamId: name} for a match's two teams. RLS-safe for anon viewers
/// (the teams of a live/complete match are readable via the gated policy).
final matchTeamNamesProvider =
    FutureProvider.family<Map<String, String>, String>((ref, matchId) async {
      final match = await ref.watch(matchProvider(matchId).future);
      if (match == null) return {};
      final ids = [match['team_a_id'], match['team_b_id']]
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return {};
      final c = ref.watch(supabaseClientProvider);
      final rows = await c.from('teams').select('id, name').inFilter('id', ids);
      return {
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          r['id'] as String: (r['name'] as String?) ?? 'Team',
      };
    });

/// The full computed innings state (the fold) - score, cards, strike, rates.
final inningsStateProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, inningsId) async {
      final c = ref.watch(supabaseClientProvider);
      final res = await c.rpc('compute_innings_state', params: {'_innings_id': inningsId});
      return Map<String, dynamic>.from(res as Map);
    });

/// Every delivery of an innings, in scoring order - the source for the ball-log
/// / corrections screen. Includes the raw scoring columns so a ball can be
/// re-specified by edit_ball/insert_ball.
final inningsDeliveriesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, inningsId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('deliveries')
          .select(
            'id, seq, bowler_id, striker_id, non_striker_id, runs_off_bat, '
            'extra_wides, extra_no_ball_penalty, extra_byes, extra_leg_byes, '
            'is_legal, wicket_type, dismissed_player_id, incoming_batter_id, fielder_id',
          )
          .eq('innings_id', inningsId)
          .order('seq');
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// Recorded wagon-wheel shots for an innings (deliveries with a shot location).
final inningsWagonProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, inningsId) async {
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('deliveries')
          .select('wagon_x, wagon_y, runs_off_bat')
          .eq('innings_id', inningsId)
          .not('wagon_x', 'is', null);
      return List<Map<String, dynamic>>.from(rows as List);
    });

/// Matches that are live or between innings, for the public "Watch live" list.
/// Readable by anyone (incl. anon) via the status-gated RLS policy; team names
/// embed through the gated teams policy.
final liveMatchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('matches')
      .select('id, status, venue, overs_limit, team_a:team_a_id(name), team_b:team_b_id(name)')
      .inFilter('status', ['live', 'innings_break'])
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(rows as List);
});

/// Registered members (real users, deduped) of either team in a match - the
/// people eligible to take over scoring via transfer_scorer.
final matchScorerCandidatesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
      final match = await ref.watch(matchProvider(matchId).future);
      if (match == null) return [];
      final ids = [match['team_a_id'], match['team_b_id']]
          .whereType<String>()
          .toList();
      if (ids.isEmpty) return [];
      final c = ref.watch(supabaseClientProvider);
      final rows = await c
          .from('team_members')
          .select('profile_id, profiles(display_name)')
          .inFilter('team_id', ids)
          .not('profile_id', 'is', null);
      // SCOR-20: you can't hand scoring to yourself.
      final me = ref.watch(currentSessionProvider)?.user.id;
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final pid = r['profile_id'] as String?;
        if (pid == null || pid == me || !seen.add(pid)) continue;
        out.add({
          'profile_id': pid,
          'name': (r['profiles'] as Map?)?['display_name'] as String? ?? 'Player',
        });
      }
      return out;
    });

/// Matches the current user is the scorer of (the Matches tab list). Embeds
/// both team names and the result so the list can render "A v B - result"
/// without a second round-trip (MTCH-1).
final myMatchesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final me = ref.watch(currentSessionProvider)?.user.id;
  if (me == null) return [];
  final c = ref.watch(supabaseClientProvider);
  final rows = await c
      .from('matches')
      .select('id, status, overs_limit, venue, created_at, owner_id, result, '
          'team_a:team_a_id(name), team_b:team_b_id(name), '
          'tournament_matches(tournament_id)')
      .eq('scorer_id', me)
      .order('created_at', ascending: false);
  // MTCH-5: tournament fixtures are managed under Tournaments, so keep the
  // personal Matches tab to the user's own casual games - drop the linked ones.
  return [
    for (final m in (rows as List).cast<Map<String, dynamic>>())
      if (!_isTournamentMatch(m)) m,
  ];
});

bool _isTournamentMatch(Map<String, dynamic> m) {
  final tm = m['tournament_matches'];
  if (tm == null) return false;
  if (tm is List) return tm.isNotEmpty;
  return true; // a single embedded object
}

/// Embedded-team name off a match row shaped {team_a:{name}} / {team_b:{name}}.
String embeddedTeamName(dynamic embed) =>
    (embed is Map ? embed['name'] as String? : null) ?? 'Team';

/// Human one-liner for a match row's stored result jsonb (used by the list).
String? matchResultLine(Map<String, dynamic> m) {
  final r = m['result'];
  if (r is! Map) return null;
  final note = r['note'] as String?;
  if (note != null && note.isNotEmpty) return note;
  return switch (r['result_type'] as String?) {
    'tie' => 'Match tied',
    'no_result' => 'No result',
    'abandoned' => 'Abandoned',
    _ => 'Completed',
  };
}
