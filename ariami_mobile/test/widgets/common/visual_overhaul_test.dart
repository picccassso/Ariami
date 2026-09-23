import 'package:ariami_mobile/utils/constants.dart';
import 'package:ariami_mobile/widgets/common/ambient_backdrop.dart';
import 'package:ariami_mobile/widgets/common/auth_card.dart';
import 'package:ariami_mobile/widgets/common/glass_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Visual Overhaul - Constants & Extensions', () {
    test('AppTheme radius constants match refined design system', () {
      expect(AppTheme.panelRadius, equals(20.0));
      expect(AppTheme.cardRadius, equals(14.0));
      expect(AppTheme.tileRadius, equals(10.0));
    });

    testWidgets('context.colors provides PlayerColors on light & dark themes', (tester) async {
      late PlayerColors darkColors;
      late PlayerColors lightColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              darkColors = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(darkColors.glowA, isNotNull);
      expect(darkColors.glowB, isNotNull);
      expect(darkColors.glowC, isNotNull);
      expect(darkColors.base, equals(const Color(0xFF08080A)));

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('light'),
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.light,
          home: Builder(
            builder: (context) {
              lightColors = context.colors;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(lightColors.glowA, isNotNull);
      expect(lightColors.base, equals(const Color(0xFFE9E9EE)));
    });

    test('AppTheme.setup() uses dark navy palette', () {
      final setupTheme = AppTheme.setup();
      expect(setupTheme.brightness, equals(Brightness.dark));
      expect(setupTheme.scaffoldBackgroundColor, equals(const Color(0xFF05070D)));
    });
  });

  group('Visual Overhaul - GlassPanel', () {
    testWidgets('renders child inside frosted container with border and background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GlassPanel(
              radius: 16,
              child: Text('Frosted Content'),
            ),
          ),
        ),
      );

      expect(find.text('Frosted Content'), findsOneWidget);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.byType(DecoratedBox), findsWidgets);
    });
  });

  group('Visual Overhaul - AuthCard and AuthBadge', () {
    testWidgets('AuthBadge renders glowing container with icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthBadge(
              icon: Icons.shield_rounded,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    });

    testWidgets('AuthCard renders child in frosted container with max width constraint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AuthCard(
              maxWidth: 420,
              child: Column(
                children: [
                  AuthBadge(icon: Icons.lock_rounded),
                  Text('Welcome'),
                  TextField(key: Key('test_input')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byKey(const Key('test_input')), findsOneWidget);
      expect(find.byType(GlassPanel), findsOneWidget);
      expect(find.byType(AuthCard), findsOneWidget);
    });
  });

  group('Visual Overhaul - AmbientBackdrop', () {
    testWidgets('renders CustomPaint with glow layout and animates on seed change', (tester) async {
      final seedNotifier = ValueNotifier<int>(42);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: seedNotifier,
            builder: (context, seed, _) {
              return Scaffold(
                body: Stack(
                  children: [
                    AmbientBackdrop(layoutSeed: seed),
                    const Text('Foreground'),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.byType(AmbientBackdrop), findsOneWidget);
      expect(find.text('Foreground'), findsOneWidget);

      // Trigger seed update (drifting glow centers)
      seedNotifier.value = 99;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.byType(AmbientBackdrop), findsOneWidget);
    });
  });
}
