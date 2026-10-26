import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'plex_style.dart';

/// Plex's clock in the top right of a page: "2:13 PM", 12-hour (the clock is
/// locked to that, PlexLocks), dimmed so it never competes with the title.
class PlexClock extends StatefulWidget {
  const PlexClock({super.key});

  /// The clock where Plex puts it on every page, for a page's Stack.
  static Widget corner() => Positioned(
    top: PlexStyle.s(24),
    right: PlexStyle.s(44),
    child: const IgnorePointer(child: PlexClock()),
  );

  @override
  State<PlexClock> createState() => _PlexClockState();
}

class _PlexClockState extends State<PlexClock> {
  static final _format = DateFormat('h:mm a');

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleTick();
  }

  /// Ticks on the minute, so the time never lags a whole minute behind.
  void _scheduleTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _format.format(_now),
      maxLines: 1,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: PlexStyle.s(13),
        fontWeight: FontWeight.w400,
        // Keeps it readable where it sits on bright backdrop art.
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
      ),
    );
  }
}
