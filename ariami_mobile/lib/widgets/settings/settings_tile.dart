import 'package:flutter/material.dart';

/// A reusable settings tile widget
/// Supports icon, title, optional subtitle, optional trailing widget, and onTap callback
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final isMaterial = Theme.of(context).platform == TargetPlatform.android;

    if (isMaterial) {
      // Material Design style for Android
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Ink(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[700]),
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else {
      // iOS style
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return GestureDetector(
        onTap: onTap,
        child: Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[700]),
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.grey[500] : Colors.grey[600],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
  }
}
