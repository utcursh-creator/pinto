import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/tournament_models.dart';
import '../data/tournament_providers.dart';
import '../../../core/ui/human_error.dart';

/// Public, login-free tournament page. One tournament_overview call feeds four
/// tabs: Table (standings + NRR), Fixtures, Bracket, and Leaders.
class TournamentPageScreen extends ConsumerStatefulWidget {
  const TournamentPageScreen({required this.tournamentId, super.key});

  final String tournamentId;

  @override
  ConsumerState<TournamentPageScreen> createState() => _TournamentPageScreenState();
}

class _TournamentPageScreenState extends ConsumerState<TournamentPageScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tournamentOverviewProvider(widget.tournamentId));
    return AdaptiveScaffold(
      // A shared link cold-starts here, outside the tab shell: offer a way
      // into the app rather than leaving the visitor on an island.
      onEnterApp: () => context.go(Routes.discover),
      title: async.value?.info.name ?? 'Tournament',
      actions: [
        IconButton(
          icon: const Icon(Icons.ios_share),
          tooltip: 'Share',
          onPressed: () => SharePlus.instance.share(ShareParams(
            text: 'Follow this tournament on Pitch: '
                'https://pitch.app/tournament/${widget.tournamentId}',
          )),
        ),
      ],
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => Center(child: Text(humanError(e, fallback: 'Could not load tournament.'))),
        data: (o) => Column(
          children: [
            if (o.info.isComplete && o.championTeamId != null)
              _ChampionBanner(o: o),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 0, label: Text('Table')),
                  ButtonSegment(value: 1, label: Text('Fixtures')),
                  ButtonSegment(value: 2, label: Text('Bracket')),
                  ButtonSegment(value: 3, label: Text('Leaders')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _TableTab(o: o),
                  _FixturesTab(o: o),
                  _BracketTab(o: o),
                  _LeadersTab(o: o),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChampionBanner extends StatelessWidget {
  const _ChampionBanner({required this.o});
  final TournamentOverview o;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final champ = o.teams.where((t) => t.teamId == o.championTeamId);
    final name = champ.isEmpty ? null : champ.first.name;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(children: [
        Icon(Icons.emoji_events, color: theme.colorScheme.onPrimaryContainer),
        const SizedBox(width: 10),
        Text('Champions: ${name ?? 'TBD'}',
            style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _TableTab extends StatelessWidget {
  const _TableTab({required this.o});
  final TournamentOverview o;

  @override
  Widget build(BuildContext context) {
    if (o.standings.isEmpty) {
      return const Center(child: Text('No results yet.'));
    }
    final theme = Theme.of(context);
    return ListView(
      key: const Key('tab_table'),
      children: [
        for (final g in o.standings) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Group ${g.label}', style: theme.textTheme.labelLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Expanded(flex: 5, child: Text('Team', style: TextStyle(fontSize: 12))),
              _h('P'), _h('Pts'),
              const Expanded(flex: 3, child: Text('NRR',
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 12))),
            ]),
          ),
          for (var i = 0; i < g.rows.length; i++)
            _StandingRowTile(
                row: g.rows[i], qualified: i < o.info.qualifiersPerGroup),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _h(String t) => Expanded(
      flex: 2,
      child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)));
}

class _StandingRowTile extends StatelessWidget {
  const _StandingRowTile({required this.row, required this.qualified});
  final StandingRow row;
  final bool qualified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
              color: qualified ? theme.colorScheme.primary : Colors.transparent,
              width: 3),
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(children: [
        Expanded(flex: 5, child: Text(row.name, style: const TextStyle(fontSize: 13))),
        Expanded(flex: 2, child: Text('${row.played}', textAlign: TextAlign.center)),
        Expanded(
            flex: 2,
            child: Text('${row.points}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(flex: 3, child: Text(row.nrrText, textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _FixturesTab extends StatelessWidget {
  const _FixturesTab({required this.o});
  final TournamentOverview o;

  @override
  Widget build(BuildContext context) {
    final sections = <(String, List<Fixture>)>[
      for (final g in o.standings)
        ('Group ${g.label}',
            o.fixtures.where((f) => f.stage == 'group' && f.groupLabel == g.label).toList()),
      ('Semifinals', o.fixturesForStage('semifinal')),
      ('Final', o.fixturesForStage('final')),
    ];
    return ListView(
      key: const Key('tab_fixtures'),
      children: [
        for (final s in sections)
          if (s.$2.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(s.$1, style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final f in s.$2) _FixtureTile(f: f),
          ],
        if (o.fixtures.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No fixtures yet.'))),
      ],
    );
  }
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.f});
  final Fixture f;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tappable = f.isLive || f.isComplete;
    return ListTile(
      dense: true,
      title: Text('${f.teamA}  v  ${f.teamB}'),
      // TOUR-4: upcoming fixtures show their date + ground when set
      subtitle: f.isUpcoming && f.scheduleLine.isNotEmpty
          ? Text(f.scheduleLine, style: theme.textTheme.bodySmall)
          : null,
      trailing: f.isLive
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(
                  color: Color(0xFFE24B4A), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('Live', style: TextStyle(color: theme.colorScheme.error)),
            ])
          : Text(f.statusLine, style: theme.textTheme.bodySmall),
      onTap: tappable ? () => context.push(Routes.viewMatch(f.matchId)) : null,
    );
  }
}

class _BracketTab extends StatelessWidget {
  const _BracketTab({required this.o});
  final TournamentOverview o;

  @override
  Widget build(BuildContext context) {
    final semis = o.fixturesForStage('semifinal');
    final fin = o.fixturesForStage('final');
    if (semis.isEmpty) {
      return const Center(
          key: Key('tab_bracket'),
          child: Padding(padding: EdgeInsets.all(24),
              child: Text('The bracket appears once the playoffs are seeded.')));
    }
    return ListView(
      key: const Key('tab_bracket'),
      padding: const EdgeInsets.all(20),
      children: [
        Text('Semifinals', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (final f in semis) _BracketMatch(f: f),
        const SizedBox(height: 16),
        Text('Final', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        if (fin.isEmpty)
          const Text('Winner SF1  v  Winner SF2', style: TextStyle(color: Colors.grey))
        else
          for (final f in fin) _BracketMatch(f: f, highlight: true),
      ],
    );
  }
}

class _BracketMatch extends StatelessWidget {
  const _BracketMatch({required this.f, this.highlight = false});
  final Fixture f;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(
            color: highlight ? theme.colorScheme.primary : theme.dividerColor,
            width: highlight ? 1 : 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(f.teamA),
        Text(f.teamB, style: TextStyle(color: theme.colorScheme.outline)),
        if (f.isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(f.statusLine, style: theme.textTheme.bodySmall),
          ),
      ]),
    );
  }
}

class _LeadersTab extends StatefulWidget {
  const _LeadersTab({this.o});
  final TournamentOverview? o;

  @override
  State<_LeadersTab> createState() => _LeadersTabState();
}

class _LeadersTabState extends State<_LeadersTab> {
  int _cat = 0;

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    if (o == null) return const SizedBox.shrink();
    final cats = <(String, List<LeaderEntry>)>[
      ('Runs', o.leaderboard.mostRuns),
      ('Wickets', o.leaderboard.mostWickets),
      ('Catches', o.leaderboard.mostCatches),
      ('4s', o.leaderboard.mostFours),
      ('6s', o.leaderboard.mostSixes),
    ];
    final entries = cats[_cat].$2;
    return ListView(
      key: const Key('tab_leaders'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(spacing: 6, children: [
            for (var i = 0; i < cats.length; i++)
              ChoiceChip(
                label: Text(cats[i].$1),
                selected: _cat == i,
                onSelected: (_) => setState(() => _cat = i),
              ),
          ]),
        ),
        if (entries.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No data yet.')))
        else
          for (var i = 0; i < entries.length; i++)
            _leaderRow(context, i + 1, entries[i]),
      ],
    );
  }

  // TOUR-7/STAT-1/STAT-2: a claimed player's row links to their career page;
  // an unclaimed guest now has a member-keyed career page of their own.
  Widget _leaderRow(BuildContext context, int rank, LeaderEntry e) {
    final claimed = e.profileId != null;
    return ListTile(
      dense: true,
      leading: Text('$rank',
          style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      title: Text(e.name),
      trailing: Text('${e.value}',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => context.push(claimed
          ? Routes.playerStats(e.profileId!)
          : Routes.guestPlayerStats(e.memberId)),
    );
  }
}
