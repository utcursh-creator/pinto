import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'brand_tokens.dart';

/// One MaterialApp drives both platforms; Cupertino widgets harmonize inside
/// it. On iOS we supply a Cupertino-tuned ThemeData, on Android a Material 3
/// one - both seeded from the brand teal.
class AppTheme {
  const AppTheme._();

  static ThemeData material() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: BrandTokens.teal),
    );
  }

  static ThemeData cupertino() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: BrandTokens.teal),
      cupertinoOverrideTheme: const CupertinoThemeData(
        primaryColor: BrandTokens.teal,
      ),
    );
  }
}
