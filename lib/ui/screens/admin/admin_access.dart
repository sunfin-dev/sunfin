import '../../../util/platform_detection.dart';

/// Whether server administration is offered here: to administrators, outside
/// Kids Mode, and not on a TV driven by a remote alone. Every way in (the
/// settings entry, the sidebar button and its switch) asks this one rule.
bool adminAreaOffered({
  required bool isAdministrator,
  required bool kidsMode,
}) => isAdministrator && !kidsMode && !PlatformDetection.isRemoteOnly;
