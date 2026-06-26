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

  /// Requests to claim a guest membership (becomes the real player behind it,
  /// pending a team admin's approval).
  Future<void> requestGuestClaim(String membershipId) =>
      _client.rpc('request_guest_claim', params: {'_membership_id': membershipId});

  /// Admin-only: approves a guest claim, transferring the guest membership to
  /// the claimer.
  Future<void> approveGuestClaim({
    required String membershipId,
    required String claimerId,
  }) =>
      _client.rpc('approve_guest_claim', params: {
        '_membership_id': membershipId,
        '_claimer': claimerId,
      });

  /// Admin-only: mints a shareable invite token for a team (registered-player
  /// invite path; guests use add-guest + claim instead).
  Future<String> createTeamInvite(String teamId) async {
    final token = await _client.rpc('create_team_invite', params: {'_team_id': teamId});
    return token as String;
  }

  /// Redeems an invite token, joining the caller to the team; returns the
  /// membership id.
  Future<String> acceptInvite(String token) async {
    final id = await _client.rpc('accept_invite', params: {'_invite_token': token});
    return id as String;
  }
}

/// The shareable link for an invite token. The path is handled in-app by the
/// `/invite/:token` route; external universal-link registration is a separate
/// (credential-boundary) deployment step, like the `/watch` share links.
String inviteLink(String token) => 'https://pitch.app/invite/$token';

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(ref.watch(supabaseClientProvider)),
);
