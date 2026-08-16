import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../dashboard/owner_access_error_panel.dart';
import 'status_pill.dart';

/// Resolves the loading / error / empty / content states that every table on
/// the dashboard shares, so each section only describes its own table.
class DataSectionBody extends StatelessWidget {
  const DataSectionBody({
    super.key,
    required this.isLoading,
    required this.error,
    required this.isEmpty,
    required this.emptyMessage,
    required this.child,
    this.showOwnerSignInCta = false,
    this.onSignInAsOwner,
  });

  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final String emptyMessage;
  final Widget child;

  /// When the error is a missing-owner-privileges 403, offer to sign in as
  /// the owner rather than just reporting the refusal.
  final bool showOwnerSignInCta;
  final VoidCallback? onSignInAsOwner;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final errorMessage = error;
    if (errorMessage != null) {
      if (showOwnerSignInCta && onSignInAsOwner != null) {
        return OwnerAccessErrorPanel(
          message: errorMessage,
          onSignInAsOwner: onSignInAsOwner!,
        );
      }
      return NoticeBanner(
        icon: Icons.error_outline_rounded,
        tone: StatusTone.negative,
        message: errorMessage,
      );
    }

    if (isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(
            emptyMessage,
            style: AppTheme.meta.copyWith(fontSize: 13.5),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return child;
  }
}

/// Consistently styled table that fills its card and only scrolls sideways
/// when the columns genuinely do not fit.
class AppDataTable extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 48,
            dataRowMaxHeight: 60,
            horizontalMargin: 0,
            columnSpacing: 28,
            dividerThickness: 1,
            headingTextStyle: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            dataTextStyle: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13.5,
            ),
            columns: columns,
            rows: rows,
          ),
        ),
      ),
    );
  }
}
