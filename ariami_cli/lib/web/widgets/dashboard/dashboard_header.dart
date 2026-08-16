import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/layout.dart';

/// Full-bleed bar whose contents line up with the page's reading column.
///
/// A plain `AppBar` spreads its title and four tabs across the whole window,
/// which on a wide monitor leaves the header floating unmoored above content
/// that is centred. This keeps both on the same grid.
class DashboardHeader extends StatelessWidget implements PreferredSizeWidget {
  const DashboardHeader({
    super.key,
    required this.tabController,
    required this.tabs,
    required this.onRefresh,
    required this.onShowQrCode,
    required this.onSignOut,
    this.username,
    this.isRefreshing = false,
  });

  final TabController tabController;
  final List<String> tabs;
  final VoidCallback onRefresh;
  final VoidCallback onShowQrCode;
  final VoidCallback onSignOut;
  final String? username;
  final bool isRefreshing;

  static const double _barHeight = 60;
  static const double _tabsHeight = 46;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight + _tabsHeight);

  @override
  Widget build(BuildContext context) {
    final widthClass = AppLayout.of(context);
    final gutter = AppLayout.gutter(widthClass);
    final isCompact = widthClass == WidthClass.compact;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.pureBlack,
        border: Border(bottom: BorderSide(color: AppTheme.borderGrey)),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppLayout.contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: _barHeight,
                    child: Row(
                      children: [
                        const _Wordmark(),
                        const Spacer(),
                        IconButton(
                          onPressed: isRefreshing ? null : onRefresh,
                          tooltip: 'Refresh',
                          icon: isRefreshing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 21),
                        ),
                        IconButton(
                          onPressed: onShowQrCode,
                          tooltip: 'Connect a device',
                          icon: const Icon(Icons.qr_code_2_rounded, size: 21),
                        ),
                        const SizedBox(width: 4),
                        _AccountMenu(
                          username: username,
                          onSignOut: onSignOut,
                          showName: !isCompact,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: _tabsHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TabBar(
                        controller: tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorWeight: 2,
                        padding: EdgeInsets.zero,
                        labelPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        // Without a radius the hover fill is a hard-edged
                        // block that reads as a rendering artefact.
                        splashBorderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                        overlayColor: WidgetStateProperty.all(
                          Colors.white.withValues(alpha: 0.05),
                        ),
                        tabs: [for (final tab in tabs) Tab(text: tab)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.music_note_rounded,
            size: 16,
            color: AppTheme.pureBlack,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'Ariami',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({
    required this.username,
    required this.onSignOut,
    required this.showName,
  });

  final String? username;
  final VoidCallback onSignOut;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final name = username ?? 'Account';
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'sign-out') onSignOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text('Signed in as $name', style: AppTheme.meta),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'sign-out',
          child: Text('Sign out'),
        ),
      ],
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: EdgeInsets.only(
            left: 5,
            right: showName ? 12 : 5,
            top: 5,
            bottom: 5,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.borderGrey),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (showName) ...[
                const SizedBox(width: 9),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: AppTheme.textSecondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
