// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';

/// Dark-first, muted earth-tone theme: readable around a fire or in glare,
/// no flashy chrome. Olive / tan / amber on dark grey.
class AppTheme {
  static const Color olive = Color(0xFF8A9A5B);
  static const Color tan = Color(0xFFC19A6B);
  static const Color amber = Color(0xFFD9A441);
  static const Color darkGrey = Color(0xFF1C1E1A);
  static const Color surfaceGrey = Color(0xFF262A24);

  /// Distinct, muted earth tones for per-member dots/callsigns.
  static const List<String> memberPalette = [
    '#C19A6B', // tan
    '#8A9A5B', // olive
    '#D9A441', // amber
    '#A0522D', // sienna
    '#6B8E23', // olive drab
    '#B7754B', // clay
    '#7C9A92', // sage teal
    '#CC7351', // terracotta
    '#9C8B5E', // khaki
    '#5F7161', // moss
    '#D98E73', // dusty coral
    '#8C7B6B', // taupe
  ];

  /// Parse a `#RRGGBB` string into a [Color].
  static Color hexColor(String hex) {
    final h = hex.replaceAll('#', '').trim();
    final value = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return Color(value ?? 0xFFC19A6B);
  }

  static ThemeData get dark {
    final scheme = const ColorScheme.dark(
      primary: olive,
      secondary: tan,
      tertiary: amber,
      surface: surfaceGrey,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkGrey,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: darkGrey,
        foregroundColor: tan,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: tan,
        ),
      ),
    );
  }
}
