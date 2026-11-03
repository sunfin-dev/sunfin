import 'dart:convert';
import 'dart:io';

import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../preference/user_preferences.dart';
import '../../util/app_distribution.dart';

enum DesktopUpdateCheckStatus {
  updateAvailable,
  upToDate,
  checkFailed,
  unsupportedPlatform,
  managedByStore,
  disabledByPreference,
  rateLimited,
  alreadyNotified,
}

class DesktopUpdateCheckResult {
  final DesktopUpdateCheckStatus status;
  final DesktopUpdateInfo? update;

  const DesktopUpdateCheckResult({
    required this.status,
    this.update,
  });
}

class DesktopUpdateInfo {
  final String version;

  /// Direct download link for the matching release asset, or the releases page
  /// when there is no single asset to pick (e.g. Linux).
  final Uri downloadUri;
  final String releaseNotesUrl;

  /// File name of the matching release asset; null when [downloadUri] is the
  /// releases page.
  final String? assetName;

  /// The release's SHA256SUMS.txt, which the in-app installer checks the
  /// download against. Null when the release has none.
  final Uri? checksumsUri;

  const DesktopUpdateInfo({
    required this.version,
    required this.downloadUri,
    required this.releaseNotesUrl,
    this.assetName,
    this.checksumsUri,
  });

  /// Whether the app can download and install this update itself.
  bool get installable => assetName != null && checksumsUri != null;
}

class AppUpdateService {
  AppUpdateService(this._store, this._userPreferences);

  static const _latestReleaseHost = 'api.github.com';
  static const _latestReleasePath = '/repos/sunfin-dev/sunfin/releases/latest';
  /// How long a declined prompt for one version stays quiet.
  static const _promptCooldown = Duration(hours: 24);

  static const _lastPromptMsKey = 'app_update_last_prompt_ms';
  static const _lastNotifiedVersionKey = 'app_update_last_notified_version';

  /// Installers that deliver their own updates. The distribution channel only
  /// records which artifact a build came from, and stores that redistribute the
  /// sideload APK unchanged (the Amazon Appstore does) would otherwise offer a
  /// GitHub download they can never install.
  static const _storeInstallerPackages = <String>{
    'com.android.vending',
    'com.amazon.venezia',
    'com.sec.android.app.samsungapps',
    'com.huawei.appmarket',
    'com.xiaomi.mipicks',
    'org.fdroid.fdroid',
  };

  static bool isStoreInstaller(String? installer) {
    return _storeInstallerPackages.contains(
      installer?.trim().toLowerCase() ?? '',
    );
  }

  final PreferenceStore _store;
  final UserPreferences _userPreferences;

  Future<DesktopUpdateInfo?> checkForUpdateIfDue() async {
    final result = await _checkForUpdate(
      respectNotificationPreference: true,
      suppressIfAlreadyNotified: true,
    );
    return result.update;
  }

  Future<DesktopUpdateInfo?> checkForUpdateNow() async {
    final result = await checkForUpdateNowDetailed();
    return result.update;
  }

  Future<DesktopUpdateCheckResult> checkForUpdateNowDetailed() {
    return _checkForUpdate(
      respectNotificationPreference: false,
      suppressIfAlreadyNotified: false,
    );
  }

  Future<DesktopUpdateCheckResult> _checkForUpdate({
    required bool respectNotificationPreference,
    required bool suppressIfAlreadyNotified,
  }) async {
    if (!AppDistribution.supportsInAppUpdates) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.unsupportedPlatform,
      );
    }

    if (await _isStoreInstalled()) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.managedByStore,
      );
    }

    if (respectNotificationPreference) {
      final notificationsEnabled = _userPreferences.get(UserPreferences.updateNotificationsEnabled);
      if (!notificationsEnabled) {
        return const DesktopUpdateCheckResult(
          status: DesktopUpdateCheckStatus.disabledByPreference,
        );
      }
    }

    // Sunfin: every start checks GitHub; the cooldown only keeps the prompt
    // for one version from coming back within a day (below).
    final now = DateTime.now().toUtc();
    final release = await _fetchLatestRelease();
    if (release == null) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.checkFailed,
      );
    }

    final currentVersion = await _currentAppVersion();
    if (!_isNewerVersion(release.version, currentVersion)) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.upToDate,
      );
    }

    final lastNotified = _store.getString(_lastNotifiedVersionKey);
    final lastPromptMs = _store.getInt(_lastPromptMsKey) ?? 0;
    final promptedRecently = now.difference(
          DateTime.fromMillisecondsSinceEpoch(lastPromptMs, isUtc: true),
        ) <
        _promptCooldown;
    if (suppressIfAlreadyNotified &&
        promptedRecently &&
        _normalizeVersion(lastNotified) == _normalizeVersion(release.version)) {
      return const DesktopUpdateCheckResult(
        status: DesktopUpdateCheckStatus.alreadyNotified,
      );
    }

    await _store.setString(_lastNotifiedVersionKey, release.version);
    await _store.setInt(_lastPromptMsKey, now.millisecondsSinceEpoch);

    final assetName = pickAssetName(
      AppDistribution.channel,
      [for (final asset in release.assets) asset.name],
    );
    _ReleaseAsset? asset;
    _ReleaseAsset? checksums;
    for (final candidate in release.assets) {
      if (candidate.name == assetName) asset = candidate;
      if (candidate.name == checksumsAssetName) checksums = candidate;
    }
    return DesktopUpdateCheckResult(
      status: DesktopUpdateCheckStatus.updateAvailable,
      update: DesktopUpdateInfo(
        version: release.version,
        downloadUri: asset != null
            ? Uri.parse(asset.downloadUrl)
            : Uri.parse(release.releaseNotesUrl),
        releaseNotesUrl: release.releaseNotesUrl,
        assetName: asset?.name,
        checksumsUri:
            checksums != null ? Uri.parse(checksums.downloadUrl) : null,
      ),
    );
  }

  /// Whether a store installed this copy. Only the Android APK channels can end
  /// up store-installed while still carrying the in-app updater.
  Future<bool> _isStoreInstalled() async {
    final channel = AppDistribution.channel;
    if (channel != DistributionChannel.apk &&
        channel != DistributionChannel.androidTvApk) {
      return false;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return isStoreInstaller(packageInfo.installerStore);
    } catch (_) {
      return false;
    }
  }

  Future<String> _currentAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      if (version.isNotEmpty) {
        return version;
      }
    } catch (_) {}
    return '0.0.0';
  }

  Future<_LatestRelease?> _fetchLatestRelease() async {
    final client = HttpClient()
      ..userAgent = 'SunfinUpdateChecker/1.0'
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client.getUrl(Uri.https(_latestReleaseHost, _latestReleasePath));
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final tagName = decoded['tag_name']?.toString();
      if (tagName == null || tagName.trim().isEmpty) {
        return null;
      }

      final htmlUrl = decoded['html_url']?.toString() ??
          'https://github.com/sunfin-dev/sunfin/releases/latest';

      final assetsJson = decoded['assets'];
      final assets = <_ReleaseAsset>[];
      if (assetsJson is List) {
        for (final asset in assetsJson) {
          if (asset is! Map) {
            continue;
          }
          final name = asset['name']?.toString();
          final downloadUrl = asset['browser_download_url']?.toString();
          if (name == null || name.isEmpty || downloadUrl == null || downloadUrl.isEmpty) {
            continue;
          }
          assets.add(_ReleaseAsset(name: name, downloadUrl: downloadUrl));
        }
      }

      return _LatestRelease(version: tagName, assets: assets, releaseNotesUrl: htmlUrl);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Name of the release file every Sunfin release ships its checksums in.
  static const checksumsAssetName = 'SHA256SUMS.txt';

  /// Release asset for a build of [channel], or null when none fits.
  ///
  /// Sunfin releases name their files `Sunfin-<ver>-android-tv.apk`,
  /// `Sunfin-<ver>-android-phone.apk` and `Sunfin-<ver>-windows-x64.zip`; the
  /// installer needs exactly that kind of file, so there is no looser fallback.
  static String? pickAssetName(
    DistributionChannel channel,
    List<String> names,
  ) {
    bool Function(String) wanted = switch (channel) {
      DistributionChannel.apk => (n) => n.endsWith('.apk') && !n.contains('tv'),
      DistributionChannel.androidTvApk =>
        (n) => n.endsWith('.apk') && n.contains('tv'),
      DistributionChannel.windows =>
        (n) => n.endsWith('.zip') && n.contains('windows-x64'),
      _ => (_) => false,
    };
    for (final name in names) {
      if (wanted(name.toLowerCase())) return name;
    }
    return null;
  }

  /// The SHA-256 that [sums] (SHA256SUMS.txt: `<hex>  <name>` per line) lists
  /// for [fileName], lower-case, or null when it lists none.
  static String? checksumFor(String sums, String fileName) {
    for (final line in const LineSplitter().convert(sums)) {
      final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line);
      if (match != null && match.group(2) == fileName) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  bool _isNewerVersion(String candidate, String current) {
    final candidateParts = _parseSemverCore(candidate);
    final currentParts = _parseSemverCore(current);
    final maxLength = candidateParts.length > currentParts.length
        ? candidateParts.length
        : currentParts.length;

    for (var i = 0; i < maxLength; i++) {
      final left = i < candidateParts.length ? candidateParts[i] : 0;
      final right = i < currentParts.length ? currentParts[i] : 0;
      if (left > right) {
        return true;
      }
      if (left < right) {
        return false;
      }
    }
    return false;
  }

  List<int> _parseSemverCore(String raw) {
    final normalized = _normalizeVersion(raw);
    if (normalized.isEmpty) {
      return const [0, 0, 0];
    }

    final core = normalized.split('-').first.split('+').first;
    final pieces = core.split('.');
    final numbers = <int>[];
    for (final piece in pieces) {
      final value = int.tryParse(piece.replaceAll(RegExp(r'[^0-9]'), ''));
      numbers.add(value ?? 0);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  String _normalizeVersion(String? raw) {
    if (raw == null) {
      return '';
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.startsWith('v') || trimmed.startsWith('V')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }
}

class _LatestRelease {
  final String version;
  final List<_ReleaseAsset> assets;
  final String releaseNotesUrl;

  const _LatestRelease({
    required this.version,
    required this.assets,
    required this.releaseNotesUrl,
  });
}

class _ReleaseAsset {
  final String name;
  final String downloadUrl;

  const _ReleaseAsset({required this.name, required this.downloadUrl});
}
