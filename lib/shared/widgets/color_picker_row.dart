// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A horizontal row of selectable earth-tone swatches for picking a member color.
class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final hex in AppTheme.memberPalette)
          GestureDetector(
            onTap: () => onChanged(hex),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.hexColor(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hex == selected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: hex == selected
                  ? const Icon(Icons.check, size: 18, color: Colors.black54)
                  : null,
            ),
          ),
      ],
    );
  }
}
