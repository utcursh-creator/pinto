import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Organizer write operations for tournaments. Reads live in
/// tournament_providers.dart. v1 bakes the 2-groups x 2-qualifiers shape.
class TournamentRepository {
  TournamentRepository(this._c);

  final SupabaseClient _c;

  Future<String> createTournament({
    required String name,
    required int overs,
    String? ballType,
    String? city,
    String? venue,
    DateTime? startsOn,
    DateTime? endsOn,
  }) async {
    final params = <String, dynamic>{
      '_name': name,
      '_overs': overs,
      '_group_count': 2,
      '_qualifiers_per_group': 2,
    };
    if (ballType != null) params['_ball_type'] = ballType;
    if (city != null && city.isNotEmpty) params['_city'] = city;
    if (venue != null && venue.isNotEmpty) params['_venue'] = venue;
    if (startsOn != null) params['_starts_on'] = _date(startsOn);
    if (endsOn != null) params['_ends_on'] = _date(endsOn);
    final id = await _c.rpc('create_tournament', params: params);
    return id as String;
  }

  Future<void> addTournamentTeam(String tournamentId, String teamId, String group) =>
      _c.rpc('add_tournament_team', params: {
        '_tournament_id': tournamentId,
        '_team_id': teamId,
        '_group_label': group,
      });

  Future<void> generateGroupFixtures(String tournamentId) =>
      _c.rpc('generate_group_fixtures', params: {'_tournament_id': tournamentId});

  Future<void> generatePlayoffs(String tournamentId) =>
      _c.rpc('generate_playoffs', params: {'_tournament_id': tournamentId});

  Future<void> advancePlayoffs(String tournamentId) =>
      _c.rpc('advance_playoffs', params: {'_tournament_id': tournamentId});

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final tournamentRepositoryProvider = Provider<TournamentRepository>(
  (ref) => TournamentRepository(ref.watch(supabaseClientProvider)),
);
