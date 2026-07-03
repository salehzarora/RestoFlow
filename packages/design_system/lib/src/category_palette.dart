import 'package:flutter/material.dart';

/// The warm menu-category accent palette (design-polish sprint).
///
/// POS menu cards and category chips tint themselves from the category's
/// accent colour. These named constants replace the raw hex literals that were
/// duplicated across the POS demo menu and the real-menu mapper — one curated,
/// food-friendly set (terracotta / teal / amber / blue / coffee / berry) that
/// stays consistent with the warm restaurant accent.
abstract final class RestoflowCategoryPalette {
  static const Color terracotta = Color(0xFFE8590C);
  static const Color teal = Color(0xFF0F766E);
  static const Color amber = Color(0xFFB45309);
  static const Color blue = Color(0xFF1D4ED8);
  static const Color coffee = Color(0xFF6F4E37);
  static const Color berry = Color(0xFF9D174D);

  /// Round-robin order used when categories are assigned colours by index.
  static const List<Color> ordered = [
    terracotta,
    teal,
    amber,
    blue,
    coffee,
    berry,
  ];
}
