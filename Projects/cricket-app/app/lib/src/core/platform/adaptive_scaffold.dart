import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

/// A page scaffold that renders a Cupertino nav bar on iOS and a Material
/// AppBar on Android, with the same title + body. Optional trailing [actions]
/// render on both; [floatingActionButton] is Material-only (iOS has no FAB -
/// surface that action via [actions] instead).
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(title),
          trailing: actions == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ),
        child: SafeArea(child: body),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
