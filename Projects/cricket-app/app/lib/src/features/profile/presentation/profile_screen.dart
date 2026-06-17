import 'package:flutter/material.dart';

import '../../../core/platform/adaptive_scaffold.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveScaffold(
      title: 'Profile',
      body: Center(child: Text('Your profile')),
    );
  }
}
