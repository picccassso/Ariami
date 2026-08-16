import 'dart:io';

import 'package:ariami_mobile/models/server_info.dart';
import 'package:ariami_mobile/screens/login_screen.dart';
import 'package:ariami_mobile/screens/register_screen.dart';
import 'package:ariami_mobile/screens/setup/manual_server_entry_screen.dart';
import 'package:ariami_mobile/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/private_sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await initPrivateSqfliteFfi('theme_contrast_test');
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AppTheme light and dark input theme contrast', () {
    test('neutral light theme has visible inputDecorationTheme and textSelectionTheme', () {
      final light = AppTheme.buildNeutralTheme(brightness: Brightness.light);
      expect(light.inputDecorationTheme.filled, isTrue);
      expect(light.inputDecorationTheme.fillColor, isNotNull);
      expect(light.textSelectionTheme.cursorColor, isNotNull);
      expect(light.textSelectionTheme.selectionColor, isNotNull);
    });

    test('neutral dark theme has visible inputDecorationTheme and textSelectionTheme', () {
      final dark = AppTheme.buildNeutralTheme(brightness: Brightness.dark);
      expect(dark.inputDecorationTheme.filled, isTrue);
      expect(dark.inputDecorationTheme.fillColor, isNotNull);
      expect(dark.textSelectionTheme.cursorColor, isNotNull);
      expect(dark.textSelectionTheme.selectionColor, isNotNull);
    });
  });

  group('Setup text fields and icons have high contrast styling under light mode', () {
    testWidgets('ManualServerEntryScreen icon, title, description, and fields are visible and white',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light, // Simulate light mode
          home: const ManualServerEntryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Top Icon should be white (not black!)
      final icon = tester.widget<Icon>(find.byIcon(Icons.dns_rounded));
      expect(icon.color, equals(Colors.white));

      // Title should be white
      final title = tester.widget<Text>(find.text('Connect manually'));
      expect(title.style?.color, equals(Colors.white));

      // Description should be white with alpha
      final desc = tester.widget<Text>(find.textContaining('Enter your server address'));
      expect(desc.style?.color, equals(Colors.white.withValues(alpha: 0.7)));

      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      expect(textFields.isNotEmpty, isTrue);

      for (final field in textFields) {
        expect(field.style?.color, equals(Colors.white));
        expect(field.decoration?.filled, isTrue);
        expect(field.decoration?.fillColor, equals(const Color(0xFF1E1E1E)));
      }
    });

    testWidgets('LoginScreen fields have visible container fill and white text',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final serverInfo = ServerInfo(
        server: '127.0.0.1',
        port: 8080,
        name: 'Test Server',
        version: '5.0.0',
        authRequired: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: LoginScreen(serverInfo: serverInfo),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.text('Welcome Back'));
      expect(title.style?.color, equals(Colors.white));

      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      expect(textFields.length, equals(2));

      for (final field in textFields) {
        expect(field.style?.color, equals(Colors.white));
        expect(field.decoration?.filled, isTrue);
        expect(field.decoration?.fillColor, equals(const Color(0xFF1E1E1E)));
      }
    });

    testWidgets('RegisterScreen fields have visible container fill and white text',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final serverInfo = ServerInfo(
        server: '127.0.0.1',
        port: 8080,
        name: 'Test Server',
        version: '5.0.0',
        authRequired: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: RegisterScreen(serverInfo: serverInfo),
        ),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.text('Create Account').first);
      expect(title.style?.color, equals(Colors.white));

      final textFields = tester.widgetList<TextField>(find.byType(TextField));
      expect(textFields.length, equals(3));

      for (final field in textFields) {
        expect(field.style?.color, equals(Colors.white));
        expect(field.decoration?.filled, isTrue);
        expect(field.decoration?.fillColor, equals(const Color(0xFF1E1E1E)));
      }
    });
  });

  group('Adaptive offline badge color resolution', () {
    testWidgets('Offline badge uses dark text on light theme and white text on dark theme',
        (tester) async {
      Widget buildBadge() {
        return Builder(
          builder: (context) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16),
                  width: 1,
                ),
              ),
              child: Text(
                'OFFLINE',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            );
          },
        );
      }

      // Light mode
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: buildBadge()),
        ),
      );
      await tester.pumpAndSettle();

      final lightText = tester.widget<Text>(find.text('OFFLINE'));
      expect(lightText.style?.color, equals(Colors.black));

      // Dark mode
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: buildBadge()),
        ),
      );
      await tester.pumpAndSettle();

      final darkText = tester.widget<Text>(find.text('OFFLINE'));
      expect(darkText.style?.color, equals(Colors.white));
    });
  });
}
