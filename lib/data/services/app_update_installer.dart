import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_service.dart';

/// Why an in-app update stopped.
enum AppUpdateFailure {
  /// The download, the checksum file or the install handoff failed.
  failed,

  /// Windows: Sunfin's folder isn't writable (e.g. under Program Files), so
  /// the update has to be installed by hand.
  folderNotWritable,
}

class AppUpdateException implements Exception {
  final AppUpdateFailure failure;
  final String message;

  const AppUpdateException(this.message,
      {this.failure = AppUpdateFailure.failed});

  @override
  String toString() => 'AppUpdateException: $message';
}

/// Installs a Sunfin release from GitHub inside the app.
///
/// The download must match the release's SHA256SUMS.txt. On Android the
/// system package installer takes over: the user confirms once, and Android
/// itself refuses an APK signed with another key than the installed app. On
/// Windows a helper script waits for Sunfin to exit, copies the new files over
/// the app folder and starts Sunfin again.
class AppUpdateInstaller {
  const AppUpdateInstaller._();

  static const _platform = MethodChannel('org.moonfin.androidtv/platform');

  /// Folder under the app's cache the download goes to. The Android
  /// FileProvider (res/xml/update_paths.xml) shares exactly this folder.
  static const _workFolder = 'sunfin_update';

  static bool get supported => Platform.isAndroid || Platform.isWindows;

  /// Downloads and installs [update], reporting download progress (0..1).
  ///
  /// On Android it returns once the system installer is open. On Windows a
  /// successful handoff ends this process. Throws [AppUpdateException].
  static Future<void> install(
    DesktopUpdateInfo update, {
    required void Function(double progress) onProgress,
  }) async {
    final assetName = update.assetName;
    final checksumsUri = update.checksumsUri;
    if (!supported || assetName == null || checksumsUri == null) {
      throw const AppUpdateException('no installable file in this release');
    }

    final expected = AppUpdateService.checksumFor(
      await _fetchText(checksumsUri),
      assetName,
    );
    if (expected == null) {
      throw AppUpdateException('$assetName is missing from the checksums');
    }

    final work = Directory(
      p.join((await getTemporaryDirectory()).path, _workFolder),
    );
    if (await work.exists()) await work.delete(recursive: true);
    await work.create(recursive: true);

    final file = File(p.join(work.path, assetName));
    await _download(update.downloadUri, file, onProgress);
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      throw AppUpdateException('checksum mismatch for $assetName');
    }

    if (Platform.isAndroid) {
      await _installApk(file);
    } else {
      await _installWindows(file, work);
    }
  }

  static Future<String> _fetchText(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AppUpdateException('HTTP ${response.statusCode} for $uri');
      }
      return await response.transform(utf8.decoder).join();
    } on SocketException catch (e) {
      throw AppUpdateException('network error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _download(
    Uri uri,
    File target,
    void Function(double progress) onProgress,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw AppUpdateException('HTTP ${response.statusCode} for $uri');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
    } on SocketException catch (e) {
      throw AppUpdateException('network error: ${e.message}');
    } on HttpException catch (e) {
      throw AppUpdateException('download error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _installApk(File apk) async {
    final opened = await _platform.invokeMethod<bool>(
      'installApk',
      {'path': apk.path},
    );
    if (opened != true) {
      throw const AppUpdateException('no package installer to open');
    }
  }

  static Future<void> _installWindows(File zip, Directory work) async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final probe = File(p.join(appDir.path, '.sunfin-update-probe'));
    try {
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      throw const AppUpdateException(
        'the app folder is not writable',
        failure: AppUpdateFailure.folderNotWritable,
      );
    }

    final unpacked = p.join(work.path, 'unpacked');
    final zipPath = zip.path;
    await Isolate.run(() => extractFileToDisk(zipPath, unpacked));

    // The zip holds one folder, Sunfin-<ver>\, with sunfin.exe inside.
    File? newExe;
    await for (final entry in Directory(unpacked).list(recursive: true)) {
      if (entry is File && p.basename(entry.path).toLowerCase() == 'sunfin.exe') {
        newExe = entry;
        break;
      }
    }
    if (newExe == null) {
      throw const AppUpdateException('sunfin.exe is missing from the zip');
    }

    final script = File(p.join(work.path, 'apply-update.ps1'));
    await script.writeAsString(_applyScript);
    // Through `cmd /c start`: powershell.exe started detached straight from
    // here never runs (tested 2026-11-03), started by cmd it does.
    await Process.start(
      'cmd.exe',
      [
        '/c',
        'start',
        '""',
        '/b',
        'powershell.exe',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-File',
        script.path,
        '-ProcessId',
        '$pid',
        '-Source',
        newExe.parent.path,
        '-Target',
        appDir.path,
      ],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  // Copies without purging: files that only the old version had stay, so a
  // folder the user also keeps other things in loses nothing.
  static const _applyScript = r'''
param([int]$ProcessId, [string]$Source, [string]$Target)
try { Wait-Process -Id $ProcessId -Timeout 60 -ErrorAction Stop } catch {}
for ($i = 0; $i -lt 10; $i++) {
  robocopy $Source $Target /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -lt 8) { break }
  Start-Sleep -Seconds 1
}
Start-Process -FilePath (Join-Path $Target 'sunfin.exe')
''';
}
