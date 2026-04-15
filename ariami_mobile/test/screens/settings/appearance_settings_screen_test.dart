import 'package:ariami_mobile/screens/settings/appearance_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStorage = <String, String>{};

  setUpAll(() {
    installSqfliteTestMocks();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map<dynamic, dynamic>? ?? const {});
      final key = args['key'] as String?;

      switch (call.method) {
        case 'read':
          if (key == null) return null;
          return secureStorage[key];
        case 'write':
          if (key != null) {
            secureStorage[key] = (args['value'] as String?) ?? '';
          }
          return null;
        case 'delete':
          if (key != null) {
            secureStorage.remove(key);
          }
          return null;
        case 'deleteAll':
          secureStorage.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStorage);
        case 'containsKey':
          if (key == null) return false;
          return secureStorage.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDownAll(() {
    uninstallSqfliteTestMocks();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  setUp(() {
    secureStorage.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'appearance settings uses source-centric options with system, light, and dark',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AppearanceSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THEME SOURCE'), findsOneWidget);
      expect(find.text('Theme Mode'), findsNothing);
      expect(find.byType(SegmentedButton), findsNothing);

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Preset Colors'), findsOneWidget);
      expect(find.text('Custom Color'), findsOneWidget);
      expect(find.text('Dynamic Cover Art'), findsOneWidget);
      expect(find.text('Static Cover Art'), findsOneWidget);
    },
  );
}
