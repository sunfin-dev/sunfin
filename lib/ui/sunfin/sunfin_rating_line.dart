import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/aggregated_item.dart';
import '../../data/services/rating_icon_provider.dart';
import '../../preference/user_preferences.dart';
import '../widgets/rating_display.dart';

/// The reference design's rating line under a title's genres (references 05, 12 and 14):
/// each score as a small logo and its number, then five stars holding the
/// viewer's own rating, hollow until they rate (user's pick A,
/// 2026-10-28, https://claude.ai/artifact/TnMTJm3n8J2xrCyoWmfYcz).
///
/// The scores are the ones the details pages already show: the server's
/// community score (drawn as the reference design draws it, a star and a percentage), its
/// critics' score, and the extra ratings when those are on. Sizes are in
/// The reference design's 960-wide units, as everything inside [SunfinHomeHeader] is.
class SunfinRatingLine extends StatelessWidget {
  final AggregatedItem item;
  final Map<String, double> extraRatings;
  final UserPreferences prefs;

  const SunfinRatingLine({
    super.key,
    required this.item,
    required this.extraRatings,
    required this.prefs,
  });

  /// Null where the line has nothing to stand for: ratings switched off, or
  /// Kids Mode, which shows none.
  static SunfinRatingLine? of({
    required AggregatedItem item,
    required Map<String, double> extraRatings,
    required UserPreferences prefs,
  }) {
    if (!prefs.effectiveShowDetailRatings) return null;
    return SunfinRatingLine(
      item: item,
      extraRatings: extraRatings,
      prefs: prefs,
    );
  }

  static const _fontSize = 11.5;
  static const _iconHeight = 10.0;
  static const _starSize = 12.0;
  static const _shadows = [Shadow(color: Color(0x66000000), blurRadius: 8)];

  static double? _inScale(double? rating, double max) {
    if (rating == null || !rating.isFinite || rating <= 0 || rating > max) {
      return null;
    }
    return rating;
  }

  @override
  Widget build(BuildContext context) {
    final scores = orderedRatings(
      ratings: extraRatings,
      communityRating: _inScale(item.communityRating, 10),
      criticRating: _inScale(item.criticRating?.toDouble(), 100)?.round(),
      enableAdditionalRatings: prefs.get(
        UserPreferences.enableAdditionalRatings,
      ),
      enabledRatings: prefs.get(UserPreferences.enabledRatings),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final score in scores) _Score(source: score.key, value: score.value),
        _Stars(rating: _inScale(item.personalRating, 10)),
      ],
    );
  }
}

class _Score extends StatelessWidget {
  final String source;
  final double value;

  const _Score({required this.source, required this.value});

  @override
  Widget build(BuildContext context) {
    final community = source == 'stars';
    final text = community
        ? '${(value * 10).round()}%'
        : RatingIconProvider.formatRating(source, value);
    final asset = community
        ? null
        : RatingIconProvider.getIconAssetPath(source, value.toInt());
    final icon = community
        ? const Icon(
            Symbols.star,
            fill: 1,
            size: SunfinRatingLine._starSize,
            color: Colors.white,
            shadows: SunfinRatingLine._shadows,
          )
        : asset == null
        ? null
        : Image.asset(
            asset,
            height: SunfinRatingLine._iconHeight,
            filterQuality: FilterQuality.medium,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon, const SizedBox(width: 3)],
        Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: SunfinRatingLine._fontSize,
            fontWeight: FontWeight.w500,
            shadows: SunfinRatingLine._shadows,
          ),
        ),
      ],
    );
  }
}

/// Five stars for a rating out of ten, in half stars; all hollow for none.
class _Stars extends StatelessWidget {
  final double? rating;

  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final halves = (rating ?? 0).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Icon(
            halves >= (i + 1) * 2
                ? Symbols.star
                : halves == i * 2 + 1
                ? Symbols.star_half
                : Symbols.star,
            fill: halves > i * 2 ? 1 : 0,
            weight: 300,
            size: SunfinRatingLine._starSize,
            color: halves > i * 2
                ? Colors.white
                : Colors.white.withValues(alpha: 0.6),
            shadows: SunfinRatingLine._shadows,
          ),
        ],
      ],
    );
  }
}
