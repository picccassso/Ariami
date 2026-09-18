import 'package:ariami_mobile/models/quality_settings.dart';
import 'package:ariami_mobile/screens/settings/downloads/widgets/download_mode_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/sqflite_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installSqfliteTestMocks();

  testWidgets('DownloadModeCard displays current quality and opens picker sheet',
      (tester) async {
    DownloadQuality? selectedQuality;
    bool? selectedOriginal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadModeCard(
            isDark: false,
            currentQuality: DownloadQuality.high,
            onQualityChanged: (q) => selectedQuality = q,
            onChanged: (orig) => selectedOriginal = orig,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download Quality'), findsOneWidget);
    expect(find.text('High (192 kbps)'), findsOneWidget);

    // Tap to open sheet
    await tester.tap(find.text('Download Quality'));
    await tester.pumpAndSettle();

    expect(find.text('DOWNLOAD QUALITY'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Original'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'High (192 kbps)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Medium (128 kbps)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Low (64 kbps)'), findsOneWidget);

    // Tap Low (64 kbps)
    await tester.tap(find.widgetWithText(ListTile, 'Low (64 kbps)'));
    await tester.pumpAndSettle();

    expect(selectedQuality, DownloadQuality.low);
    expect(selectedOriginal, isFalse);
  });

  testWidgets(
      'DownloadModeCard backward compatibility with downloadOriginal=true',
      (tester) async {
    DownloadQuality? selectedQuality;
    bool? selectedOriginal;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadModeCard(
            isDark: true,
            downloadOriginal: true,
            onQualityChanged: (q) => selectedQuality = q,
            onChanged: (orig) => selectedOriginal = orig,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download Quality'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);

    // Tap to open sheet
    await tester.tap(find.text('Download Quality'));
    await tester.pumpAndSettle();

    // Select Original
    await tester.tap(find.widgetWithText(ListTile, 'Original'));
    await tester.pumpAndSettle();

    expect(selectedQuality, DownloadQuality.original);
    expect(selectedOriginal, isTrue);
  });

  testWidgets(
      'DownloadModeCard backward compatibility with legacy downloadQuality=medium',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DownloadModeCard(
            isDark: false,
            downloadQuality: StreamingQuality.medium,
            downloadOriginal: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download Quality'), findsOneWidget);
    expect(find.text('Medium (128 kbps)'), findsOneWidget);
  });
}
