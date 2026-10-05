import 'package:flutter/material.dart';

/// Design tokens for strict monochrome palette and UI constants.
abstract final class EditorTokens {
  // Palette only:
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0xFF111111);
  static const Color elevated = Color(0xFF1C1C1C);
  static const Color border = Color(0xFF2A2A2A);
  static const Color text = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF8C8C8C);
  static const Color faint = Color(0xFF5A5A5A);

  // Track colors (monochrome pattern / shade based)
  static const Color videoTrack = Color(0xFF1C1C1C);
  static const Color audioTrack = Color(0xFF161616);
  static const Color textTrack = Color(0xFF222222);
  static const Color fxTrack = Color(0xFF282828);
  static const Color drawTrack = Color(0xFF1E1E1E);

  // Minimum UI constraints
  static const double minTouchTarget = 44.0;
  static const double minFontSize = 11.0;
  static const double borderWidth = 1.0;
  static const double selectedBorderWidth = 2.0;

  // Selected state border
  static const Border sideSelected = Border(
    top: BorderSide(color: text, width: selectedBorderWidth),
    bottom: BorderSide(color: text, width: selectedBorderWidth),
    left: BorderSide(color: text, width: selectedBorderWidth),
    right: BorderSide(color: text, width: selectedBorderWidth),
  );
}
