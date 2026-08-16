import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';
import '../ui/data_section.dart';
import '../ui/section.dart';

class UserActivitySection extends StatelessWidget {
  const UserActivitySection({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.error,
    this.showOwnerSignInCta = false,
    this.onSignInAsOwner,
  });

  final List<UserActivityRow> rows;
  final bool isLoading;
  final String? error;
  final bool showOwnerSignInCta;
  final VoidCallback? onSignInAsOwner;

  @override
  Widget build(BuildContext context) {
    return Section(
      title: 'Downloads and transcoding',
      description: 'What each signed-in account is pulling from this server '
          'right now.',
      child: AppCard(
        child: DataSectionBody(
          isLoading: isLoading,
          error: error,
          showOwnerSignInCta: showOwnerSignInCta,
          onSignInAsOwner: onSignInAsOwner,
          isEmpty: rows.isEmpty,
          emptyMessage: 'Nothing downloading or transcoding right now.',
          child: AppDataTable(
            columns: const [
              DataColumn(label: Text('User')),
              DataColumn(label: Text('Downloading')),
              DataColumn(label: Text('Queued')),
              DataColumn(label: Text('Transcoding')),
            ],
            rows: rows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(Text(row.username)),
                      DataCell(_Count(
                        value: row.activeDownloads,
                        highlight: row.isDownloading,
                        highlightColor: AppTheme.success,
                      )),
                      DataCell(Text('${row.queuedDownloads}')),
                      DataCell(_Count(
                        value: row.inFlightDownloadTranscodes,
                        highlight: row.isTranscoding,
                        highlightColor: AppTheme.warning,
                      )),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

/// A count that only takes on colour when it is actually non-idle.
class _Count extends StatelessWidget {
  const _Count({
    required this.value,
    required this.highlight,
    required this.highlightColor,
  });

  final int value;
  final bool highlight;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$value',
      style: TextStyle(
        color: highlight ? highlightColor : AppTheme.textTertiary,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
    );
  }
}
