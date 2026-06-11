// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Caravan Electric, LLC.

/// A single feature returned by a tap-to-identify query (a trail, road, or
/// land parcel), normalised for display in a popup.
class FeatureInfo {
  const FeatureInfo({
    required this.title,
    required this.subtitle,
    required this.lines,
  });

  final String title;
  final String subtitle;
  final List<String> lines;
}
