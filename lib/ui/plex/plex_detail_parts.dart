import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/aggregated_item.dart';
import '../../util/language_codes.dart';
import '../../util/language_matching.dart';
import 'plex_style.dart';

// The pieces Plex's details pages share: the Play pill, the round buttons
// beside it, the media chips on the right, and the memo that keeps a page's
// parts from being built again for nothing.

/// Hands back the widget built last time for a part of a page while its
/// inputs are unchanged, so Flutter skips that whole subtree. Details pages
/// rebuild on every view-model update while they open (ratings, extras,
/// similar titles), 33-47 ms a time on the Shield when everything is laid
/// out again.
///
/// Inputs compare with ==, and a list counts as unchanged while it holds the
/// same entries, since the cast and crew are filtered afresh on every read.
class PlexMemo {
  final _last = <Object, (List<Object?>, Widget)>{};

  Widget call(Object key, List<Object?> inputs, Widget Function() build) {
    final last = _last[key];
    if (last != null && sameInputs(last.$1, inputs)) return last.$2;
    final built = build();
    _last[key] = (inputs, built);
    return built;
  }

  static bool sameInputs(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x == y) continue;
      if (x is List && y is List && x.length == y.length) {
        var same = true;
        for (var j = 0; j < x.length && same; j++) {
          same = identical(x[j], y[j]);
        }
        if (same) continue;
      }
      return false;
    }
    return true;
  }
}

/// Plex's Play: a round button that opens into a white "Play" pill when
/// focused (reference 12 focused, 13 not).
class PlexPlayButton extends StatelessWidget {
  final String label;
  final bool focused;
  final double size;

  const PlexPlayButton({
    super.key,
    required this.label,
    required this.focused,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final color = focused ? Colors.black : Colors.white;
    return AnimatedSize(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      alignment: Alignment.centerLeft,
      child: Container(
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: focused
            ? EdgeInsets.only(left: PlexStyle.s(10), right: PlexStyle.s(14))
            : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: focused ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.play_arrow, size: size * 0.6, fill: 1, color: color),
            if (focused) ...[
              SizedBox(width: PlexStyle.s(4)),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: PlexStyle.s(12.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PlexRoundButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final bool focused;
  final double size;

  const PlexRoundButton({
    super.key,
    required this.icon,
    required this.filled,
    required this.focused,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.12),
      ),
      child: Icon(
        icon,
        size: size * 0.55,
        fill: filled ? 1 : 0,
        color: focused ? Colors.black : Colors.white,
      ),
    );
  }
}

/// A title's resolution, audio and subtitle, as Plex shows them at the right
/// of the buttons: "1080p", "English (EAC3 5.1)", "English (SRT)".
class PlexMediaChips extends StatelessWidget {
  final AggregatedItem item;

  const PlexMediaChips({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final streams = item.mediaStreams;
    Map<String, dynamic>? pick(String type) {
      final ofType = streams.where((s) => s['Type'] == type).toList();
      if (ofType.isEmpty) return null;
      return ofType.where((s) => s['IsDefault'] == true).firstOrNull ??
          (type == 'Subtitle' ? null : ofType.first);
    }

    final audio = pick('Audio');
    final subtitle = pick('Subtitle');
    final chips = <Widget>[
      if (item.videoResolution case final resolution?)
        PlexChip(text: resolution),
      if (audio != null)
        PlexChip(icon: Icons.volume_up_rounded, text: streamLabel(audio, audio: true)),
      if (subtitle != null)
        PlexChip(icon: Icons.subtitles_outlined, text: streamLabel(subtitle)),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) SizedBox(width: PlexStyle.s(8)),
          chips[i],
        ],
      ],
    );
  }

  /// "English (EAC3 5.1)", "German Forced (PGS)": the language, then the
  /// codec and, for audio, the channel layout.
  static String streamLabel(Map<String, dynamic> stream, {bool audio = false}) {
    final forced = !audio && stream['IsForced'] == true;
    final language = '${_languageName(stream['Language'] as String?)}'
        '${forced ? ' Forced' : ''}';
    var codec = (stream['Codec'] as String?)?.toUpperCase() ?? '';
    codec = _codecNames[codec] ?? codec;
    final parts = [
      codec,
      if (audio) _layout(stream),
    ].where((p) => p.isNotEmpty).join(' ');
    return parts.isEmpty ? language : '$language ($parts)';
  }

  static const _codecNames = {'SUBRIP': 'SRT', 'PGSSUB': 'PGS'};

  /// The server's DisplayTitle doesn't reliably start with the language (a
  /// track titled "Stereo" puts that first), so the name comes from the code.
  static String _languageName(String? code) {
    final iso3 = toIso3Language(normalizeLanguage(code));
    if (iso3.isEmpty) return 'Unknown';
    final terminology = _bibliographicCodes[iso3] ?? iso3;
    return kIso6392Languages[terminology] ?? iso3.toUpperCase();
  }

  /// Older ISO 639-2/B codes, which files often carry, to the /T codes the
  /// name table uses.
  static const _bibliographicCodes = {
    'alb': 'sqi', 'arm': 'hye', 'baq': 'eus', 'bur': 'mya', 'chi': 'zho',
    'cze': 'ces', 'dut': 'nld', 'fre': 'fra', 'geo': 'kat', 'ger': 'deu',
    'gre': 'ell', 'ice': 'isl', 'mac': 'mkd', 'mao': 'mri', 'may': 'msa',
    'per': 'fas', 'rum': 'ron', 'slo': 'slk', 'tib': 'bod', 'wel': 'cym',
  };

  static String _layout(Map<String, dynamic> stream) {
    final layout = (stream['ChannelLayout'] as String?)?.trim() ?? '';
    if (layout.isNotEmpty) {
      return layout.toLowerCase() == 'stereo' ? 'Stereo' : layout;
    }
    final channels = stream['Channels'];
    if (channels is int) return channels == 2 ? 'Stereo' : '$channels ch';
    return '';
  }
}

class PlexChip extends StatelessWidget {
  final IconData? icon;
  final String text;

  const PlexChip({super.key, this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final size = PlexStyle.s(10);
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: PlexStyle.s(5),
          vertical: PlexStyle.s(2),
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(PlexStyle.s(3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: size * 1.2, color: Colors.white),
              SizedBox(width: PlexStyle.s(4)),
            ],
            Text(
              text,
              maxLines: 1,
              style: TextStyle(color: Colors.white, fontSize: size),
            ),
          ],
        ),
      ),
    );
  }
}
