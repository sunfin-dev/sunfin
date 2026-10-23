import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/plex_locks.dart';
import 'package:moonfin/preference/preference_constants.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:moonfin/util/platform_detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<UserPreferences> _prefs([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  final store = PreferenceStore();
  await store.init();
  return UserPreferences(store);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => PlatformDetection.setTvMode(false));

  group('on TV', () {
    setUp(() => PlatformDetection.setTvMode(true));

    test('the look reads as Plex whatever is stored', () async {
      final prefs = await _prefs({
        'pref_navbar_position': 'top',
        'pref_detail_screen_style': 'modern',
        'app_theme_id': 'neonPulse',
        'pref_use_24_hour_clock': true,
        'pref_hide_backdrops_in_libraries': false,
      });

      expect(prefs.get(UserPreferences.navbarPosition), NavbarPosition.left);
      expect(
        prefs.get(UserPreferences.detailScreenStyle),
        DetailScreenStyle.nouveau,
      );
      expect(prefs.get(UserPreferences.visualTheme), VisualThemeId.moonfin);
      expect(prefs.get(UserPreferences.use24HourClock), isFalse);
      expect(prefs.get(UserPreferences.hideBackdropsInLibraries), isTrue);
    });

    test('a locked setting ignores a new choice', () async {
      final prefs = await _prefs();
      await prefs.set(UserPreferences.posterSize, PosterSize.extraLarge);

      expect(
        prefs.get(UserPreferences.posterSize),
        UserPreferences.posterSize.defaultValue,
      );
    });

    test('the stored value stays readable for the sync', () async {
      final prefs = await _prefs({'pref_navbar_position': 'top'});

      expect(prefs.getStored(UserPreferences.navbarPosition), NavbarPosition.top);
    });

    test('content choices stay the user\'s', () async {
      final prefs = await _prefs({
        'pref_show_genres_button': true,
        'pref_merge_continue_watching_next_up': true,
      });

      expect(prefs.get(UserPreferences.showGenresButton), isTrue);
      expect(prefs.get(UserPreferences.mergeContinueWatchingNextUp), isTrue);
    });

    test('per-row image types are locked by prefix', () {
      final pref = UserPreferences.homeRowImageType(HomeSectionType.resume);
      expect(PlexLocks.isLocked(pref.key), isTrue);
    });
  });

  test('off TV nothing is locked', () async {
    final prefs = await _prefs({'pref_navbar_position': 'top'});

    expect(PlexLocks.isLocked(UserPreferences.navbarPosition.key), isFalse);
    expect(prefs.get(UserPreferences.navbarPosition), NavbarPosition.top);
  });
}
