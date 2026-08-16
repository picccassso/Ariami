import 'package:flutter/material.dart';

import '../ui/page_shell.dart';

/// Scrollable tab body that preserves scroll position when switching tabs.
///
/// Wraps its content in the shared [PageShell] so every tab keeps the same
/// reading column as the header above it.
class DashboardKeepAliveTab extends StatefulWidget {
  const DashboardKeepAliveTab({super.key, required this.child});

  final Widget child;

  @override
  State<DashboardKeepAliveTab> createState() => _DashboardKeepAliveTabState();
}

class _DashboardKeepAliveTabState extends State<DashboardKeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PageShell(child: widget.child);
  }
}
