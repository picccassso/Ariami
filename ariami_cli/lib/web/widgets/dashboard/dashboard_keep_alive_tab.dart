import 'package:flutter/material.dart';

/// Scrollable tab body that preserves scroll position when switching tabs.
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
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: isNarrow ? 16 : 24,
        vertical: isNarrow ? 20 : 32,
      ),
      child: widget.child,
    );
  }
}
