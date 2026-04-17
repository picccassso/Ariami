import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

/// Table of currently active user download/transcode activity.
class UserActivityTable extends StatelessWidget {
  const UserActivityTable({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.rows,
  });

  final bool isLoading;
  final String? errorMessage;
  final List<UserActivityRow> rows;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (errorMessage != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          errorMessage!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }

    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: const Text(
          'No active download/transcode activity.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('User')),
                DataColumn(label: Text('Downloading')),
                DataColumn(label: Text('Queue')),
                DataColumn(label: Text('Transcoding')),
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
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
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
                                  : Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }
}
