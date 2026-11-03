import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/services/app_update_service.dart';
import 'package:moonfin/util/app_distribution.dart';

void main() {
  // The files of the published 0.12.5 release.
  const assets = [
    'SHA256SUMS.txt',
    'Sunfin-0.12.5-android-phone.apk',
    'Sunfin-0.12.5-android-tv.apk',
    'Sunfin-0.12.5-windows-x64.zip',
  ];

  group('AppUpdateService.pickAssetName', () {
    test('each channel gets its own file', () {
      expect(
        AppUpdateService.pickAssetName(DistributionChannel.androidTvApk, assets),
        'Sunfin-0.12.5-android-tv.apk',
      );
      expect(
        AppUpdateService.pickAssetName(DistributionChannel.apk, assets),
        'Sunfin-0.12.5-android-phone.apk',
      );
      expect(
        AppUpdateService.pickAssetName(DistributionChannel.windows, assets),
        'Sunfin-0.12.5-windows-x64.zip',
      );
    });

    test('channels without a Sunfin release file get nothing', () {
      expect(
        AppUpdateService.pickAssetName(DistributionChannel.aab, assets),
        isNull,
      );
      expect(
        AppUpdateService.pickAssetName(DistributionChannel.unknown, assets),
        isNull,
      );
    });

    test('a release missing the file gets nothing, not another platform\'s', () {
      expect(
        AppUpdateService.pickAssetName(
          DistributionChannel.androidTvApk,
          const ['Sunfin-0.13.1-android-phone.apk', 'SHA256SUMS.txt'],
        ),
        isNull,
      );
      expect(
        AppUpdateService.pickAssetName(
          DistributionChannel.windows,
          const ['Sunfin-0.13.1-android-tv.apk'],
        ),
        isNull,
      );
    });
  });

  group('AppUpdateService.checksumFor', () {
    const tv =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
    const sums = '$tv  Sunfin-0.12.5-android-tv.apk\r\n'
        'B1B2C3D4E5F60718293A4B5C6D7E8F90A1B2C3D4E5F60718293A4B5C6D7E8F90'
        ' *Sunfin-0.12.5-windows-x64.zip\n';

    test('finds the line for the file, lower-cased', () {
      expect(
        AppUpdateService.checksumFor(sums, 'Sunfin-0.12.5-android-tv.apk'),
        tv,
      );
      expect(
        AppUpdateService.checksumFor(sums, 'Sunfin-0.12.5-windows-x64.zip'),
        'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
      );
    });

    test('a file the list doesn\'t name has no checksum', () {
      expect(
        AppUpdateService.checksumFor(sums, 'Sunfin-0.12.5-android-phone.apk'),
        isNull,
      );
      expect(AppUpdateService.checksumFor('not a checksum list', 'x'), isNull);
    });
  });

  test('an update without its checksum file is not installable', () {
    final withSums = DesktopUpdateInfo(
      version: 'v0.13.1',
      downloadUri: Uri.parse('https://example.invalid/a.apk'),
      releaseNotesUrl: 'https://example.invalid/notes',
      assetName: 'a.apk',
      checksumsUri: Uri.parse('https://example.invalid/SHA256SUMS.txt'),
    );
    final withoutSums = DesktopUpdateInfo(
      version: 'v0.13.1',
      downloadUri: Uri.parse('https://example.invalid/a.apk'),
      releaseNotesUrl: 'https://example.invalid/notes',
      assetName: 'a.apk',
    );
    expect(withSums.installable, isTrue);
    expect(withoutSums.installable, isFalse);
  });
}
