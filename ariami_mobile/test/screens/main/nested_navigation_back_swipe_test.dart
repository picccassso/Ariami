import 'package:ariami_mobile/models/api_models.dart';
import 'package:ariami_mobile/screens/main/album_page_opener.dart';
import 'package:ariami_mobile/screens/main/artist_page_opener.dart';
import 'package:ariami_mobile/screens/main/library_navigator.dart';
import 'package:ariami_mobile/screens/main/nested_tab_navigator.dart';
import 'package:ariami_mobile/screens/main/search_navigator.dart';
import 'package:ariami_mobile/screens/main/settings_navigator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMainNavigationScreen extends StatefulWidget {
  const _FakeMainNavigationScreen({this.initialIndex = 1});

  final int initialIndex;

  @override
  State<_FakeMainNavigationScreen> createState() =>
      _FakeMainNavigationScreenState();
}

class _FakeMainNavigationScreenState extends State<_FakeMainNavigationScreen> {
  late int _currentIndex;
  bool exitedApp = false;

  GlobalKey<NavigatorState> get _currentNavigatorKey {
    switch (_currentIndex) {
      case 0:
        return libraryNavigatorKey;
      case 1:
        return searchNavigatorKey;
      case 2:
        return settingsNavigatorKey;
      default:
        return libraryNavigatorKey;
    }
  }

  void _openArtistPage(String artistName) {
    final nav = _currentNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamed('/artist', arguments: artistName);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentNavigatorKey.currentState
            ?.pushNamed('/artist', arguments: artistName);
      });
    }
  }

  void _openAlbumPage(AlbumModel album) {
    final nav = _currentNavigatorKey.currentState;
    if (nav != null) {
      nav.pushNamed('/album', arguments: album);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _currentNavigatorKey.currentState
            ?.pushNamed('/album', arguments: album);
      });
    }
  }

  void _exitApp() {
    exitedApp = true;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    ArtistPageOpener().register(_openArtistPage);
    AlbumPageOpener().register(_openAlbumPage);
  }

  @override
  void dispose() {
    ArtistPageOpener().unregister(_openArtistPage);
    AlbumPageOpener().unregister(_openAlbumPage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_currentIndex) {
        0 => NestedTabNavigator(
            navigatorKey: libraryNavigatorKey,
            onBackAtRoot: _exitApp,
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: Text('Library: ${settings.name}')),
            ),
          ),
        1 => NestedTabNavigator(
            navigatorKey: searchNavigatorKey,
            onBackAtRoot: () => setState(() => _currentIndex = 0),
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: Text('Search: ${settings.name}')),
            ),
          ),
        2 => NestedTabNavigator(
            navigatorKey: settingsNavigatorKey,
            onBackAtRoot: () => setState(() => _currentIndex = 0),
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) =>
                  Scaffold(body: Text('Settings: ${settings.name}')),
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

AlbumModel _testAlbum(
        {String title = 'Test Album', String artist = 'Test Artist'}) =>
    AlbumModel(
      id: 'album-1',
      title: title,
      artist: artist,
      songCount: 10,
      duration: 1800,
    );

void main() {
  group('Nested navigation back swipe and tab preservation', () {
    testWidgets(
        'Opening artist page from Search tab stays in Search and back returns to Search',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: _FakeMainNavigationScreen(initialIndex: 1),
        ),
      );
      await tester.pump();

      expect(find.text('Search: /'), findsOneWidget);

      // Open artist page
      ArtistPageOpener().open('Daft Punk');
      await tester.pump();
      await tester.pump();

      // Artist page is shown within the Search tab navigator
      expect(find.text('Search: /artist'), findsOneWidget);
      expect(searchNavigatorKey.currentState?.canPop(), isTrue);

      // Simulate system back gesture (swipe back)
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      final handled = await widgetsAppState.didPopRoute();
      await tester.pump();

      expect(handled, isTrue);
      // Returned to the Search root, did not switch tabs or exit app
      expect(find.text('Search: /'), findsOneWidget);
      final screenState = tester.state<_FakeMainNavigationScreenState>(
          find.byType(_FakeMainNavigationScreen));
      expect(screenState._currentIndex, 1);
      expect(screenState.exitedApp, isFalse);
    });

    testWidgets(
        'Opening album page from Search tab stays in Search and back returns to Search',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: _FakeMainNavigationScreen(initialIndex: 1),
        ),
      );
      await tester.pump();

      expect(find.text('Search: /'), findsOneWidget);

      // Open album page
      AlbumPageOpener().open(_testAlbum());
      await tester.pump();
      await tester.pump();

      expect(find.text('Search: /album'), findsOneWidget);
      expect(searchNavigatorKey.currentState?.canPop(), isTrue);

      // Simulate system back gesture
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      final handled = await widgetsAppState.didPopRoute();
      await tester.pump();

      expect(handled, isTrue);
      expect(find.text('Search: /'), findsOneWidget);
      final screenState = tester.state<_FakeMainNavigationScreenState>(
          find.byType(_FakeMainNavigationScreen));
      expect(screenState._currentIndex, 1);
      expect(screenState.exitedApp, isFalse);
    });

    testWidgets(
        'Opening artist page from Settings tab stays in Settings and back returns to Settings',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: _FakeMainNavigationScreen(initialIndex: 2),
        ),
      );
      await tester.pump();

      expect(find.text('Settings: /'), findsOneWidget);

      ArtistPageOpener().open('Justice');
      await tester.pump();
      await tester.pump();

      expect(find.text('Settings: /artist'), findsOneWidget);
      expect(settingsNavigatorKey.currentState?.canPop(), isTrue);

      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      final handled = await widgetsAppState.didPopRoute();
      await tester.pump();

      expect(handled, isTrue);
      expect(find.text('Settings: /'), findsOneWidget);
      final screenState = tester.state<_FakeMainNavigationScreenState>(
          find.byType(_FakeMainNavigationScreen));
      expect(screenState._currentIndex, 2);
      expect(screenState.exitedApp, isFalse);
    });

    testWidgets(
        'NestedTabNavigator uses actual navigator canPop to prevent stale notification exits',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      var exited = false;

      await tester.pumpWidget(
        MaterialApp(
          home: NestedTabNavigator(
            navigatorKey: navKey,
            onBackAtRoot: () => exited = true,
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(body: Text('Route: ${settings.name}')),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Route: /'), findsOneWidget);

      // Push nested route
      navKey.currentState!.pushNamed('/artist');
      await tester.pump();

      expect(find.text('Route: /artist'), findsOneWidget);

      // Simulate an incoming stale NavigationNotification(canHandlePop: false)
      // dispatched from a descendant or race condition
      const NavigationNotification(canHandlePop: false).dispatch(
        tester.element(find.text('Route: /artist')),
      );
      await tester.pump();

      // Attempt to pop via system back gesture
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pump();

      // It must pop the nested route, NOT exit the app
      expect(exited, isFalse);
      expect(find.text('Route: /'), findsOneWidget);
    });

    testWidgets(
        'Root route with PopScope intercepts back gesture before onBackAtRoot',
        (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      var exited = false;
      var selectionActive = true;
      var batchSelectionReleased = false;

      await tester.pumpWidget(
        MaterialApp(
          home: NestedTabNavigator(
            navigatorKey: navKey,
            onBackAtRoot: () => exited = true,
            onGenerateRoute: (settings) => MaterialPageRoute(
              settings: settings,
              builder: (_) => StatefulBuilder(
                builder: (context, setState) => PopScope(
                  canPop: !selectionActive,
                  onPopInvokedWithResult: (didPop, result) {
                    if (didPop) return;
                    if (selectionActive) {
                      selectionActive = false;
                      batchSelectionReleased = true;
                      setState(() {});
                    }
                  },
                  child: Scaffold(
                    body: Text(
                      selectionActive
                          ? 'Batch Selection Active'
                          : 'Normal Library',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Batch Selection Active'), findsOneWidget);
      expect(batchSelectionReleased, isFalse);
      expect(exited, isFalse);

      // First back gesture (e.g. Android back swipe): should release batch selection, not exit
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      final handledFirst = await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(handledFirst, isTrue);
      expect(batchSelectionReleased, isTrue);
      expect(find.text('Normal Library'), findsOneWidget);
      expect(exited, isFalse);

      // Second back gesture: batch selection already released, should call onBackAtRoot
      final handledSecond = await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      expect(handledSecond, isTrue);
      expect(exited, isTrue);
    });
  });
}
