import 'package:flutter_test/flutter_test.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:moonfin/preference/library_nicknames.dart';
import 'package:server_core/server_core.dart' show serverResponseRewriter;
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> views() => {
  'Items': [
    {'Id': 'lib4k', 'Name': 'movies_4k', 'Type': 'CollectionFolder'},
    {'Id': 'libtv', 'Name': 'TV Shows', 'Type': 'CollectionFolder'},
  ],
};

void main() {
  late PreferenceStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = PreferenceStore();
    await store.init();
    LibraryNicknames.install(store);
  });

  tearDown(() => serverResponseRewriter = null);

  test('renames a nicknamed library in a views answer, nothing else', () async {
    await LibraryNicknames.set(
      'lib4k',
      nickname: '4K Movies',
      serverName: 'movies_4k',
    );
    final answer = views();
    serverResponseRewriter!(answer);
    final items = answer['Items'] as List;
    expect(items[0]['Name'], '4K Movies');
    expect(items[1]['Name'], 'TV Shows');
  });

  test('renames a library fetched on its own', () async {
    await LibraryNicknames.set(
      'lib4k',
      nickname: '4K Movies',
      serverName: 'movies_4k',
    );
    final item = {'Id': 'lib4k', 'Name': 'movies_4k', 'Type': 'CollectionFolder'};
    LibraryNicknames.rewrite(item);
    expect(item['Name'], '4K Movies');
  });

  test('leaves a movie that shares nothing but an id shape alone', () async {
    await LibraryNicknames.set(
      'lib4k',
      nickname: '4K Movies',
      serverName: 'movies_4k',
    );
    final movie = {'Id': 'lib4k', 'Name': 'Dune', 'Type': 'Movie'};
    LibraryNicknames.rewrite(movie);
    expect(movie['Name'], 'Dune');
  });

  test('an empty nickname goes back to the server name, and it persists',
      () async {
    await LibraryNicknames.set(
      'lib4k',
      nickname: '4K Movies',
      serverName: 'movies_4k',
    );
    // A fresh start reads the saved names back.
    LibraryNicknames.install(store);
    expect(LibraryNicknames.nicknameFor('lib4k'), '4K Movies');
    expect(LibraryNicknames.serverNameFor('lib4k'), 'movies_4k');

    await LibraryNicknames.set('lib4k', nickname: '  ', serverName: 'movies_4k');
    LibraryNicknames.install(store);
    expect(LibraryNicknames.nicknameFor('lib4k'), isNull);
    final answer = views();
    serverResponseRewriter!(answer);
    expect((answer['Items'] as List)[0]['Name'], 'movies_4k');
  });
}
