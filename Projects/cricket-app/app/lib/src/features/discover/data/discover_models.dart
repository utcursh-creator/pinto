import 'package:flutter/foundation.dart';

/// The discovery query: a geo anchor + radius + optional mode/flair filters.
/// Value-equal so it can key a Riverpod family (re-fetches when it changes).
@immutable
class DiscoverQuery {
  const DiscoverQuery({
    required this.lat,
    required this.lng,
    this.radiusM = 25000,
    this.mode,
    this.flair,
  });

  final double lat;
  final double lng;
  final double radiusM;
  final String? mode;
  final String? flair;

  DiscoverQuery copyWith({double? radiusM, Object? mode = _unset, Object? flair = _unset}) =>
      DiscoverQuery(
        lat: lat,
        lng: lng,
        radiusM: radiusM ?? this.radiusM,
        mode: mode == _unset ? this.mode : mode as String?,
        flair: flair == _unset ? this.flair : flair as String?,
      );

  static const _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is DiscoverQuery &&
      other.lat == lat &&
      other.lng == lng &&
      other.radiusM == radiusM &&
      other.mode == mode &&
      other.flair == flair;

  @override
  int get hashCode => Object.hash(lat, lng, radiusM, mode, flair);
}

/// Display labels + helpers for the matchmaking enums.
class LfLabels {
  const LfLabels._();

  static const Map<String, String> modes = {
    'player_seeking_team': 'Need a team',
    'team_seeking_players': 'Need players',
    'team_seeking_opponent': 'Need an opponent',
  };

  static const Map<String, String> flairs = {
    'loser_pays': 'Loser pays',
    'practice_match': 'Practice match',
    'corporate_match': 'Corporate match',
  };

  static const Map<String, String> skills = {
    'beginner': 'Beginner',
    'intermediate': 'Intermediate',
    'advanced': 'Advanced',
  };

  static String mode(String? v) => modes[v] ?? '';
  static String flair(String? v) => flairs[v] ?? '';
  static String skill(String? v) => skills[v] ?? '';

  // DISC-7: the server coarsens to 100m, so anything close reads as 0 - show a
  // friendly "Nearby" instead of "0 m", and km for longer ranges.
  static String distance(num? approxM) {
    if (approxM == null) return '';
    final m = approxM.round();
    if (m < 100) return 'Nearby';
    if (m < 1000) return '$m m';
    return '${(m / 1000).toStringAsFixed(1)} km';
  }

  /// Friendly "when" for a post's match_at (e.g. "Sun 6 Jul, 9:00 am").
  static String matchWhen(dynamic matchAt) {
    if (matchAt == null) return '';
    final dt = matchAt is DateTime
        ? matchAt
        : DateTime.tryParse(matchAt.toString())?.toLocal();
    if (dt == null) return '';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? 'am' : 'pm';
    final mins = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}, $h12:$mins $ampm';
  }

  /// The metadata chips a post can show: "20 ov", skill, "N players", when.
  static List<String> metaChips({
    int? overs,
    String? skillLevel,
    int? slotsNeeded,
    dynamic matchAt,
  }) =>
      [
        if (overs != null) '$overs ov',
        if (skillLevel != null && skillLevel.isNotEmpty) skill(skillLevel),
        if (slotsNeeded != null && slotsNeeded > 0)
          '$slotsNeeded player${slotsNeeded == 1 ? '' : 's'} needed',
        if (matchWhen(matchAt).isNotEmpty) matchWhen(matchAt),
      ];
}
