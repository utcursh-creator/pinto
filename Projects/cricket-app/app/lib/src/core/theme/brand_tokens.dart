import 'package:flutter/widgets.dart';

/// Brand design tokens shared across both platform looks. The single teal
/// accent stands in place of the system blue/red on each platform.
class BrandTokens {
  const BrandTokens._();

  static const Color teal = Color(0xFF0F6E56);
  static const Color tealLight = Color(0xFFE1F5EE);
  static const Color scoreDark = Color(0xFF0F2E26);

  // Flair chip colors (background / foreground).
  static const Color flairAmberBg = Color(0xFFFAEEDA);
  static const Color flairAmberFg = Color(0xFF854F0B);
  static const Color flairGrayBg = Color(0xFFD3D1C7);
  static const Color flairGrayFg = Color(0xFF444441);
  static const Color flairBlueBg = Color(0xFFE6F1FB);
  static const Color flairBlueFg = Color(0xFF0C447C);
}
