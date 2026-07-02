import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../../identity/presentation/initials_avatar.dart';
import '../data/discover_providers.dart';

/// Find a player or team by name (MISS-3). A player row opens their career page;
/// a team row opens the team page.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));
    return AdaptiveScaffold(
      title: 'Search',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Players or teams',
                border: const OutlineInputBorder(),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _query.trim().length < 2
                ? const Center(child: Text('Type at least 2 letters to search.'))
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator.adaptive()),
                    error: (e, _) => Center(child: Text('Search failed.\n$e')),
                    data: (rows) => rows.isEmpty
                        ? const Center(child: Text('No players or teams found.'))
                        : ListView.separated(
                            itemCount: rows.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) => _row(context, rows[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> r) {
    final kind = r['kind'] as String?;
    final id = r['id'] as String;
    final name = (r['name'] as String?) ?? '';
    final subtitle = r['subtitle'] as String?;
    final isTeam = kind == 'team';
    return ListTile(
      leading: InitialsAvatar(
          name: name, photoUrl: r['photo_url'] as String?, radius: 20),
      title: Text(name),
      subtitle: Text(isTeam
          ? 'Team${subtitle != null && subtitle.isNotEmpty ? '  -  $subtitle' : ''}'
          : 'Player'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
          isTeam ? Routes.teamPage(id) : Routes.playerStats(id)),
    );
  }
}
