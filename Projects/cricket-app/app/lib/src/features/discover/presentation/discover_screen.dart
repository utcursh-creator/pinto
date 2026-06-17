import 'package:flutter/material.dart';

import '../../../core/platform/adaptive_scaffold.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveScaffold(
      title: 'Discover',
      body: Center(child: Text('Find a game near you')),
    );
  }
}
