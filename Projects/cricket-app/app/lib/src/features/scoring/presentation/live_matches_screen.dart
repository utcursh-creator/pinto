import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/platform/adaptive_scaffold.dart';
import '../../../core/routing/routes.dart';
import '../data/match_providers.dart';
import '../../../core/ui/human_error.dart';

/// Public "Watch live" list: matches currently live or between innings, open to
/// anyone (login-free). Tapping opens the read-only viewer.
class LiveMatchesScreen extends ConsumerWidget {
  const LiveMatchesScreen({super.key});

  String _name(Map<String, dynamic> m, String key) =>
      (m[key] as Map<String, dynamic>?)?['name'] as String? ?? 'Team';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveMatchesProvider);
    return AdaptiveScaffold(
      title: 'Watch live',
      body: RefreshIndicator.adaptive(
        onRefresh: () async => ref.invalidate(liveMatchesProvider),
        child: live.when(
          loading: () =>
              const Center(child: CircularProgressIndicator.adaptive()),
          error: (e, _) => ListView(
            children: [Center(child: Text(humanError(e, fallback: 'Could not load live matches.')))],
          ),
          data: (rows) => rows.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('No live matches right now.')),
                  ],
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = rows[i];
                    final status = m['status'] as String?;
                    return ListTile(
                      leading: const Icon(Icons.sensors, color: Color(0xFFD7263D)),
                      title: Text('${_name(m, 'team_a')} v ${_name(m, 'team_b')}'),
                      subtitle: Text(
                        '${status == 'innings_break' ? 'innings break' : 'live'}'
                        '${m['venue'] != null ? '  -  ${m['venue']}' : ''}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push(Routes.viewMatch(m['id'] as String)),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
