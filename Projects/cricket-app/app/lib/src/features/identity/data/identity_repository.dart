import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_providers.dart';

/// Write operations for the Identity surface (profile edits + team creation).
/// Reads live in identity_providers.dart.
class IdentityRepository {
  IdentityRepository(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentSession?.user.id;
    if (id == null) {
      throw StateError('No authenticated user');
    }
    return id;
  }

  Future<void> updateMyProfile(Map<String, dynamic> fields) async {
    await _client.from('profiles').update(fields).eq('id', _uid);
  }

  /// Creates a team (and the caller's captain membership, server-side) and
  /// returns the new team id.
  Future<String> createTeam({required String name, String? city}) async {
    final id = await _client.rpc(
      'create_team',
      params: {'_name': name, if (city != null && city.isNotEmpty) '_city': city},
    );
    return id as String;
  }

  /// Adds a guest member (no account) to a team; returns the membership id.
  Future<String> addGuest({
    required String teamId,
    required String guestName,
  }) async {
    final id = await _client.rpc(
      'add_guest_member',
      params: {'_team_id': teamId, '_guest_name': guestName},
    );
    return id as String;
  }
}

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(ref.watch(supabaseClientProvider)),
);
