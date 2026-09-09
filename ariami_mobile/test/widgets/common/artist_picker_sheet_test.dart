import 'package:ariami_mobile/widgets/common/artist_link.dart';
import 'package:ariami_mobile/widgets/common/artist_picker_sheet.dart';
import 'package:ariami_mobile/widgets/common/queue_action_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(installSqfliteTestMocks);

  tearDown(() {
    dismissQueueActionConfirmation();
  });

  group('openArtistOrPicker', () {
    testWidgets('single artist returns immediately without opening a bottom sheet',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await openArtistOrPicker(
                    context,
                    artistName: 'Daft Punk',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await _pumpFrames(tester);

      expect(result, 'Daft Punk');
      expect(find.text('Artists'), findsNothing);
    });

    testWidgets('protected multi-word band name is treated as single artist',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await openArtistOrPicker(
                    context,
                    artistName: 'Earth, Wind & Fire',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await _pumpFrames(tester);

      expect(result, 'Earth, Wind & Fire');
      expect(find.text('Artists'), findsNothing);
    });

    testWidgets('multiple artists opens bottom sheet and selecting returns artist',
        (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await openArtistOrPicker(
                    context,
                    artistName: 'Costi, Alina',
                    songTitle: 'Necazuri si suparari',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await _pumpFrames(tester);

      // Verify bottom sheet is shown with "Artists" header and both options
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Necazuri si suparari'), findsOneWidget);
      expect(find.text('Costi'), findsOneWidget);
      expect(find.text('Alina'), findsOneWidget);

      // Tap "Alina"
      await tester.tap(find.text('Alina'));
      await _pumpFrames(tester);

      expect(result, 'Alina');
      expect(find.text('Artists'), findsNothing);
    });

    testWidgets('multiple artists dismissed returns null', (tester) async {
      String? result = 'initial';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await openArtistOrPicker(
                    context,
                    artistName: 'Alice & Bob',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await _pumpFrames(tester);

      expect(find.text('Artists'), findsOneWidget);

      // Dismiss by tapping the modal barrier (outside the sheet)
      await tester.tapAt(const Offset(20, 20));
      await _pumpFrames(tester);

      expect(result, isNull);
      expect(find.text('Artists'), findsNothing);
    });
  });

  group('ArtistLink with multi-artist', () {
    testWidgets('tapping multi-artist link opens picker and navigates on selection',
        (tester) async {
      Object? pushedArguments;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == '/artist') {
              pushedArguments = settings.arguments;
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Text('Artist: ${settings.arguments}'),
                ),
              );
            }
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: ArtistLink(name: 'Alice, Bob'),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('Alice, Bob'));
      await _pumpFrames(tester);

      // Picker is open, navigation hasn't happened yet
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(pushedArguments, isNull);

      // Tap Bob
      await tester.tap(find.text('Bob'));
      await _pumpFrames(tester);

      expect(pushedArguments, 'Bob');
      expect(find.text('Artist: Bob'), findsOneWidget);
    });

    testWidgets('dismissing picker on multi-artist link does not navigate',
        (tester) async {
      Object? pushedArguments;

      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (settings) {
            if (settings.name == '/artist') {
              pushedArguments = settings.arguments;
              return MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Artist Page')),
              );
            }
            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: ArtistLink(name: 'Alice, Bob'),
              ),
            );
          },
        ),
      );

      await tester.tap(find.text('Alice, Bob'));
      await _pumpFrames(tester);

      expect(find.text('Artists'), findsOneWidget);

      // Dismiss barrier
      await tester.tapAt(const Offset(20, 20));
      await _pumpFrames(tester);

      expect(pushedArguments, isNull);
      expect(find.text('Artist Page'), findsNothing);
    });
  });
}
