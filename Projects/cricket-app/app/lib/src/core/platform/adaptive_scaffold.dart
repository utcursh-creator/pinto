import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'platform.dart';

/// A page scaffold that renders a Cupertino nav bar on iOS and a Material
/// AppBar on Android, with the same title + body. Optional trailing [actions]
/// render on both; [floatingActionButton] is Material-only (iOS has no FAB -
/// surface that action via [actions] instead).
///
/// [onEnterApp] is for the public, top-level, shareable screens (`/watch`,
/// `/player`, `/tournament`, `/invite`, `/join-tournament`). Those sit OUTSIDE
/// the tab shell so that deep links cold-start reliably, which means a visitor
/// who opened one from a shared link has no tab bar and nothing to pop: they
/// are looking at a single page with no way into the rest of the app. When
/// there is genuinely nothing behind this screen, offer a way in.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.onEnterApp,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final VoidCallback? onEnterApp;

  /// Only shown when this screen is the whole stack - otherwise the ordinary
  /// back button is the right (and expected) affordance.
  Widget? _leading(BuildContext context) {
    if (onEnterApp == null) return null;
    if (ModalRoute.of(context)?.canPop ?? false) return null;
    return IconButton(
      icon: const Icon(Icons.home_outlined),
      tooltip: 'Open Pitch',
      onPressed: onEnterApp,
    );
  }

  @override
  Widget build(BuildContext context) {
    final leading = _leading(context);
    if (isCupertino(context)) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(title),
          leading: leading,
          trailing: actions == null
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: actions!),
        ),
        // CupertinoPageScaffold provides no Material ancestor NOR a Scaffold,
        // so Material widgets (TextField, ListTile, Chip, ...) crash and -
        // far worse - ScaffoldMessenger SnackBars have nowhere to display:
        // every toast in the app was silently invisible on iOS. A transparent
        // Scaffold fixes both without changing the Cupertino look.
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(child: body),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions, leading: leading),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}
