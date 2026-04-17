import 'package:ariami_core/ariami_core.dart';
import 'package:ariami_desktop/widgets/user_activity_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('shows empty activity message when there are no rows',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserActivityTable(
          isLoading: false,
          errorMessage: null,
          rows: <UserActivityRow>[],
        ),
      ),
    );

    expect(find.text('No active download/transcode activity.'), findsOneWidget);
  });

  testWidgets('shows loading indicator when loading', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserActivityTable(
          isLoading: true,
          errorMessage: null,
          rows: <UserActivityRow>[],
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders active user activity rows', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const UserActivityTable(
          isLoading: false,
          errorMessage: null,
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
        ),
      ),
    );

    expect(find.text('alex'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });
}
