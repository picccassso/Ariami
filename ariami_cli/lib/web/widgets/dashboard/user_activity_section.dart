import 'package:flutter/material.dart';

import '../../services/web_api_client.dart';
import '../../utils/constants.dart';

class UserActivitySection extends StatelessWidget {
  const UserActivitySection({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.error,
  });

  final List<UserActivityRow> rows;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'USER ACTIVITY',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else if (error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            )
          else if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No active download/transcode activity.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                dataTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),
                columns: const [
                  DataColumn(label: Text('USER')),
                  DataColumn(label: Text('DOWNLOADING')),
                  DataColumn(label: Text('QUEUE')),
                  DataColumn(label: Text('TRANSCODING')),
                ],
                rows: rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(Text(row.username)),
                          DataCell(
                            Text(
                              '${row.activeDownloads}',
                              style: TextStyle(
                                color: row.isDownloading
                                    ? Colors.greenAccent
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          DataCell(Text('${row.queuedDownloads}')),
                          DataCell(
                            Text(
                              '${row.inFlightDownloadTranscodes}',
                              style: TextStyle(
                                color: row.isTranscoding
                                    ? Colors.orangeAccent
                                    : AppTheme.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}
