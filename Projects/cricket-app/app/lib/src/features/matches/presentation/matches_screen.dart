import 'package:flutter/material.dart';

import '../../../core/platform/adaptive_scaffold.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveScaffold(
      title: 'Matches',
      body: Center(child: Text('Your matches')),
    );
  }
}
