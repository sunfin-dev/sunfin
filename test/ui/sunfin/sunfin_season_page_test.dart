import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/data/models/aggregated_item.dart';
import 'package:moonfin/ui/sunfin/sunfin_season_page.dart';

AggregatedItem _episode(int number, {bool played = false, int position = 0}) =>
    AggregatedItem(
      id: 'e$number',
      serverId: 's',
      rawData: {
        'Id': 'e$number',
        'Type': 'Episode',
        'IndexNumber': number,
        'UserData': {'Played': played, 'PlaybackPositionTicks': position},
      },
    );

void main() {
  group('the episode a season opens on', () {
    test('is the one part way through', () {
      final episodes = [
        _episode(1, played: true),
        _episode(2),
        _episode(3, position: 1000),
      ];
      expect(sunfinNextToWatch(episodes)?.id, 'e3');
    });

    test('else the first one not watched', () {
      final episodes = [_episode(1, played: true), _episode(2), _episode(3)];
      expect(sunfinNextToWatch(episodes)?.id, 'e2');
    });

    test('else the first, once everything is watched', () {
      final episodes = [_episode(1, played: true), _episode(2, played: true)];
      expect(sunfinNextToWatch(episodes)?.id, 'e1');
    });

    test('is nothing for an empty season', () {
      expect(sunfinNextToWatch(const []), isNull);
    });
  });

  group('media chips', () {
    test('name the audio language from its code, not the track title', () {
      // A track titled "Stereo" put that ahead of the language in the
      // server's DisplayTitle, which read as "Stereo (TRUEHD Stereo)".
      final audio = {
        'Type': 'Audio',
        'Language': 'jpn',
        'DisplayTitle': 'Stereo - Japanese - TrueHD',
        'Codec': 'truehd',
        'ChannelLayout': 'stereo',
      };
      expect(sunfinStreamLabel(audio, audio: true), 'Japanese (TRUEHD Stereo)');
    });

    test('read the older language codes files often carry', () {
      final audio = {
        'Type': 'Audio',
        'Language': 'ger',
        'Codec': 'eac3',
        'ChannelLayout': '5.1',
      };
      expect(sunfinStreamLabel(audio, audio: true), 'German (EAC3 5.1)');
    });

    test('mark forced subtitles and use the short codec names', () {
      final subtitle = {
        'Type': 'Subtitle',
        'Language': 'ger',
        'Codec': 'PGSSUB',
        'IsForced': true,
      };
      expect(sunfinStreamLabel(subtitle), 'German Forced (PGS)');
      expect(
        sunfinStreamLabel({'Type': 'Subtitle', 'Language': 'eng', 'Codec': 'subrip'}),
        'English (SRT)',
      );
    });

    test('fall back when the language is missing', () {
      expect(
        sunfinStreamLabel({'Type': 'Audio', 'Codec': 'aac', 'Channels': 2}, audio: true),
        'Unknown (AAC Stereo)',
      );
    });
  });
}
