import 'package:flutter/material.dart';

/// Shown while the auth + profile state resolves; the router redirect moves
/// the user off it once the gate is known.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
