import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../identity/presentation/initials_avatar.dart';
import '../data/stats_models.dart';
import '../data/stats_providers.dart';

/// Public, login-free career stats for one player (keyed by profile id, or -
/// STAT-2 - by team_members.id for an unclaimed guest via [isGuest]):
/// identity header, batting + bowling cards, a fielding line and a last-5 form
/// strip. Undefined ratios render as '-'. Reached from the Profile tab, team
/// roster rows, leaderboards, and a shareable `/player/:id` deep link.
class PlayerStatsScreen extends ConsumerWidget {
  const PlayerStatsScreen(
      {required this.profileId, this.isGuest = false, super.key});

  final String profileId;
  final bool isGuest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(isGuest
        ? guestPlayerStatsProvider(profileId)
        : playerStatsProvider(profileId));
    return AdaptiveScaffold(
      title: async.value?.identity.displayName ?? 'Player',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load stats.\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (stats) => RefreshIndicator.adaptive(
          onRefresh: () async => ref.invalidate(isGuest
              ? guestPlayerStatsProvider(profileId)
              : playerStatsProvider(profileId)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              _Header(stats: stats),
              if (stats.isEmpty)
                const Padding(
                  key: Key('stats_empty'),
                  padding: EdgeInsets.fromLTRB(20, 32, 20, 8),
                  child: Text(
                    'No stats yet.\nPlay a match and the career numbers will show up here.',
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                _BattingSection(card: stats.batting),
                _BowlingSection(card: stats.bowling),
                _FieldingSection(line: stats.fielding),
                if (stats.recentForm.isNotEmpty)
                  _FormStrip(entries: stats.recentForm),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    final id = stats.identity;
    final theme = Theme.of(context);
    final styleLabel = switch (id.battingStyle) {
      'right' => 'Right-hand bat',
      'left' => 'Left-hand bat',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          InitialsAvatar(name: id.displayName, photoUrl: id.photoUrl, radius: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(id.displayName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  [
                    '${stats.matches} ${stats.matches == 1 ? 'match' : 'matches'}',
                    ?styleLabel,
                  ].join('  -  '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(title, style: Theme.of(context).textTheme.labelLarge),
        ),
        child,
      ],
    );
  }
}

/// A wrap of compact label/value stat tiles.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});

  final List<(String, String)> stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Wrap(
        children: [for (final s in stats) _StatTile(label: s.$1, value: s.$2)],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 86,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _BattingSection extends StatelessWidget {
  const _BattingSection({required this.card});

  final BattingCard card;

  @override
  Widget build(BuildContext context) {
    return _Section(
      key: const Key('stats_batting'),
      title: 'Batting',
      child: _StatGrid(stats: [
        ('Inns', '${card.innings}'),
        ('NO', '${card.notOuts}'),
        ('Runs', '${card.runs}'),
        ('HS', card.highestLabel),
        ('Avg', fmtRatio(card.average)),
        ('SR', fmtRatio(card.strikeRate)),
        ('100s', '${card.hundreds}'),
        ('50s', '${card.fifties}'),
        ('4s', '${card.fours}'),
        ('6s', '${card.sixes}'),
        ('Ducks', '${card.ducks}'),
      ]),
    );
  }
}

class _BowlingSection extends StatelessWidget {
  const _BowlingSection({required this.card});

  final BowlingCard card;

  @override
  Widget build(BuildContext context) {
    return _Section(
      key: const Key('stats_bowling'),
      title: 'Bowling',
      child: _StatGrid(stats: [
        ('Inns', '${card.innings}'),
        ('Overs', card.overs),
        ('Wkts', '${card.wickets}'),
        ('Runs', '${card.runs}'),
        ('BBI', card.bestLabel),
        ('Avg', fmtRatio(card.average)),
        ('Econ', fmtRatio(card.economy)),
        ('SR', fmtRatio(card.strikeRate)),
        ('Maidens', '${card.maidens}'),
        ('4w', '${card.fourWickets}'),
        ('5w', '${card.fiveWickets}'),
      ]),
    );
  }
}

class _FieldingSection extends StatelessWidget {
  const _FieldingSection({required this.line});

  final FieldingLine line;

  @override
  Widget build(BuildContext context) {
    return _Section(
      key: const Key('stats_fielding'),
      title: 'Fielding',
      child: _StatGrid(stats: [
        ('Catches', '${line.catches}'),
        ('Run-outs', '${line.runOuts}'),
        ('Stumpings', '${line.stumpings}'),
      ]),
    );
  }
}

class _FormStrip extends StatelessWidget {
  const _FormStrip({required this.entries});

  final List<FormEntry> entries;

  @override
  Widget build(BuildContext context) {
    return _Section(
      key: const Key('stats_form'),
      title: 'Recent form',
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) => _FormChip(entry: entries[i]),
        ),
      ),
    );
  }
}

class _FormChip extends StatelessWidget {
  const _FormChip({required this.entry});

  final FormEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            entry.batLabel,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            entry.wickets > 0 ? '${entry.wickets}w' : 'bat',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
