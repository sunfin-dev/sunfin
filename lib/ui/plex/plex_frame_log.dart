import 'dart:async';
import 'dart:ui';

import 'package:flutter/scheduler.dart';

/// Plexfin: frame timing on the device, for tuning how smooth the app feels
/// (user, 2026-10-26). Writes one line per second of animation to logcat
/// (`adb logcat -s flutter`), tagged `PlexfinFrames`, and stays silent while
/// nothing moves:
///
///   PlexfinFrames /home n=58 slow=3 build<=9.1 raster<=21.4 span<=25.0 p90=14.2
///
/// slow = frames that missed the display's frame budget in build or raster.
/// The max values say which thread was late: build is the UI thread (layout,
/// rebuilds), raster the GPU thread (painting, images, shaders).
abstract final class PlexFrameLog {
  static bool _started = false;
  static String Function()? _route;
  static final List<FrameTiming> _window = [];
  static int? _windowStartUs;
  static Timer? _idleFlush;

  static void start({required String Function() route}) {
    if (_started) return;
    _started = true;
    _route = route;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static double get _budgetMs {
    final displays = PlatformDispatcher.instance.displays;
    final hz = displays.isEmpty ? 60.0 : displays.first.refreshRate;
    return 1000 / (hz > 0 ? hz : 60.0);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final startUs = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      _windowStartUs ??= startUs;
      if (startUs - _windowStartUs! >= 1000000) _flush();
      _windowStartUs ??= startUs;
      _window.add(timing);
    }
    // The last second of an animation is written once things go quiet.
    _idleFlush?.cancel();
    _idleFlush = Timer(const Duration(milliseconds: 1200), _flush);
  }

  static void _flush() {
    final frames = List<FrameTiming>.of(_window);
    _window.clear();
    _windowStartUs = null;
    if (frames.isEmpty) return;
    final budget = _budgetMs;
    double ms(Duration d) => d.inMicroseconds / 1000;
    var slow = 0;
    var maxBuild = 0.0;
    var maxRaster = 0.0;
    var maxSpan = 0.0;
    final spans = <double>[];
    for (final f in frames) {
      final build = ms(f.buildDuration);
      final raster = ms(f.rasterDuration);
      final span = ms(f.totalSpan);
      if (build > budget || raster > budget) slow++;
      if (build > maxBuild) maxBuild = build;
      if (raster > maxRaster) maxRaster = raster;
      if (span > maxSpan) maxSpan = span;
      spans.add(span);
    }
    spans.sort();
    final p90 = spans[((spans.length - 1) * 0.9).round()];
    String f1(double v) => v.toStringAsFixed(1);
    String route;
    try {
      route = _route?.call() ?? '?';
    } catch (_) {
      route = '?';
    }
    // ignore: avoid_print
    print(
      'PlexfinFrames $route n=${frames.length} slow=$slow '
      'build<=${f1(maxBuild)} raster<=${f1(maxRaster)} '
      'span<=${f1(maxSpan)} p90=${f1(p90)} budget=${f1(budget)}',
    );
  }
}
