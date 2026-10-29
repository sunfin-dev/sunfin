import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:mocktail/mocktail.dart';
import 'package:moonfin/data/repositories/search_repository.dart';
import 'package:moonfin/data/viewmodels/search_view_model.dart';
import 'package:moonfin/preference/user_preferences.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements MediaServerClient {}

class _MockItemsApi extends Mock implements ItemsApi {}

void main() {
  late _MockClient client;
  late _MockItemsApi itemsApi;

  /// What the server holds, by type: far more seasons than anything else,
  /// as a library of shows has.
  final library = <String, int>{'Season': 300, 'Episode': 300, 'Movie': 3};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = PreferenceStore();
    await store.init();
    GetIt.instance.registerSingleton<UserPreferences>(UserPreferences(store));

    client = _MockClient();
    itemsApi = _MockItemsApi();
    when(() => client.itemsApi).thenReturn(itemsApi);
    when(() => client.gamesApi).thenReturn(null);
    when(() => itemsApi.getPersons(
      searchTerm: any(named: 'searchTerm'),
      limit: any(named: 'limit'),
      fields: any(named: 'fields'),
      enableImageTypes: any(named: 'enableImageTypes'),
    )).thenAnswer((_) async => {'Items': []});
    // A server that ranks seasons first and honours the type filter and the
    // limit, like Jellyfin does.
    when(() => itemsApi.getItems(
      searchTerm: any(named: 'searchTerm'),
      parentId: any(named: 'parentId'),
      includeItemTypes: any(named: 'includeItemTypes'),
      limit: any(named: 'limit'),
      recursive: any(named: 'recursive'),
      fields: any(named: 'fields'),
      studios: any(named: 'studios'),
    )).thenAnswer((call) async {
      final types = call.namedArguments[#includeItemTypes] as List<String>?;
      final limit = call.namedArguments[#limit] as int? ?? 1 << 30;
      final items = [
        for (final entry in library.entries)
          if (types == null || types.contains(entry.key))
            for (var i = 0; i < entry.value; i++)
              {'Id': '${entry.key}-$i', 'Type': entry.key, 'Name': 'Season $i'},
      ];
      return {'Items': items.take(limit).toList()};
    });
  });

  tearDown(() => GetIt.instance.reset());

  Future<SearchViewModel> search(String query) async {
    final vm = SearchViewModel(SearchRepository(client), client);
    addTearDown(vm.dispose);
    vm.searchImmediate(query);
    while (vm.state == SearchState.loading) {
      await pumpEventQueue();
    }
    return vm;
  }

  List<String> typesShown(SearchViewModel vm) => [
    for (final group in vm.results) ...group.itemTypes,
  ];

  test('every type gets its own share, so a few movies are not crowded out',
      () async {
    final vm = await search('s');

    final movies = vm.results.singleWhere((g) => g.itemTypes.contains('Movie'));
    expect(movies.items, hasLength(3));
    final episodes =
        vm.results.singleWhere((g) => g.itemTypes.contains('Episode'));
    expect(episodes.items, hasLength(24));
  });

  test('seasons and folders are not searched', () async {
    final vm = await search('s');

    expect(typesShown(vm), isNot(contains('Season')));
    expect(typesShown(vm), isNot(contains('Folder')));
    verifyNever(() => itemsApi.getItems(
      searchTerm: any(named: 'searchTerm'),
      parentId: any(named: 'parentId'),
      includeItemTypes: const ['Season'],
      limit: any(named: 'limit'),
      recursive: any(named: 'recursive'),
      fields: any(named: 'fields'),
      studios: any(named: 'studios'),
    ));
  });
}
