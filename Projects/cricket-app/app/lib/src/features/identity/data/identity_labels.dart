/// Maps backend enum values to display labels for the Identity UI.
class IdentityLabels {
  const IdentityLabels._();

  static String battingStyle(String? value) => switch (value) {
    'right' => 'Right-hand bat',
    'left' => 'Left-hand bat',
    _ => '',
  };

  static String playingRole(String? value) => switch (value) {
    'batter' => 'Batter',
    'bowler' => 'Bowler',
    'all_rounder' => 'Allrounder',
    'keeper' => 'Wicket-keeper',
    _ => '',
  };

  static String teamRole(String? value) => switch (value) {
    'captain' => 'Captain',
    'admin' => 'Admin',
    'player' => 'Player',
    _ => '',
  };

  /// A one-line subtitle like "Mumbai - Right-hand bat - Allrounder".
  static String profileSubtitle(Map<String, dynamic> profile) {
    final parts = <String>[
      if ((profile['city'] as String?)?.isNotEmpty ?? false)
        profile['city'] as String,
      if (battingStyle(profile['batting_style'] as String?).isNotEmpty)
        battingStyle(profile['batting_style'] as String?),
      if (playingRole(profile['playing_role'] as String?).isNotEmpty)
        playingRole(profile['playing_role'] as String?),
    ];
    return parts.join('  -  ');
  }

  static String initials(String? displayName) {
    final name = (displayName ?? '').trim();
    if (name.isEmpty) return '?';
    final words = name.split(RegExp(r'\s+'));
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1))
        .toUpperCase();
  }
}
