import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../util/platform_detection.dart';

/// The folder holding the offline database, created if missing.
///
/// Plexfin: Windows keeps it with the app's own data (%APPDATA%\Plexfin\
/// Plexfin) instead of Documents. Windows Defender's Controlled Folder Access
/// blocks unknown apps from writing to Documents, which left the app hanging
/// before its first frame, and Documents\Moonfin would be shared with a stock
/// Moonfin install.
Future<Directory> offlineDatabaseDirectory() async {
  final Directory dir;
  if (PlatformDetection.isWindows) {
    final support = await getApplicationSupportDirectory();
    dir = Directory('${support.path}/DB');
  } else {
    final docs = PlatformDetection.isAppleTV
        ? await getApplicationCacheDirectory()
        : await getApplicationDocumentsDirectory();
    dir = Directory('${docs.path}/Moonfin/DB');
  }
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}
