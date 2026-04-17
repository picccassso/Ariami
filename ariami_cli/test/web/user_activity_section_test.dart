import 'package:ariami_cli/web/services/web_api_client.dart';
import 'package:ariami_cli/web/widgets/dashboard/user_activity_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('shows empty message when no activity rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserActivitySection(
          rows: <UserActivityRow>[],
          isLoading: false,
          error: null,
        ),
      ),
    );

    expect(find.text('No active download/transcode activity.'), findsOneWidget);
  });

  testWidgets('renders activity row values', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserActivitySection(
          rows: <UserActivityRow>[
            UserActivityRow(
              userId: 'u1',
              username: 'alex',
              isDownloading: true,
              isTranscoding: true,
              activeDownloads: 2,
              queuedDownloads: 1,
              inFlightDownloadTranscodes: 1,
            ),
          ],
          isLoading: false,
          error: null,
        ),
      ),
    );

    expect(find.text('alex'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });
}
