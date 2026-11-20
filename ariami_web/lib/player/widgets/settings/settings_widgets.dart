import 'package:flutter/material.dart';

import '../../services/sensitive_info_service.dart';
import '../../theme/motion.dart';
import '../../theme/player_theme.dart';
import '../hover_surface.dart';

export 'desktop_segmented_control.dart';

/// A small sentence-case label naming a group of controls, in place of the
/// tracked-out capitals the settings used to use.
class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: PlayerTheme.heading(14, color: context.colors.textSecondary),
      );
}

/// One section of a settings page: a hairline rule, the section's title and
/// what it does, then its controls. Sections are separated by rules rather
/// than boxed as cards, like the rest of the player.
class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: PlayerTheme.heading(20, color: colors.textPrimary),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        // Keeps explanations to a readable line length.
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Text(
                          subtitle!,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 16),
            child!,
          ],
        ],
      ),
    );
  }
}

class SettingsChoiceChip extends StatelessWidget {
  const SettingsChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: HoverSurface(
          active: selected,
          base: Colors.transparent,
          highlight: colors.textPrimary,
          borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: AnimatedDefaultTextStyle(
            duration: Motion.fast,
            style: TextStyle(
              fontFamily: PlayerTheme.bodyFamily,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: selected ? colors.base : colors.textPrimary,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// A colour to pick, drawn as a printer's swatch: a small square, ringed in
/// ink while chosen.
class ColorSwatchButton extends StatelessWidget {
  const ColorSwatchButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          width: 36,
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
            border: Border.all(
              color: selected ? context.colors.textPrimary : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(PlayerTheme.cardRadius - 1),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsKeyValueRow extends StatelessWidget {
  const SettingsKeyValueRow(this.label, this.value,
      {super.key, this.sensitive = false});
  final String label;
  final String value;

  final bool sensitive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: sensitive
                ? SensitiveText(value)
                : Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Shows [value], or a mask until revealed. The eye button reveals just this
/// value (until the section is left); the General setting reveals all of them.
class SensitiveText extends StatefulWidget {
  const SensitiveText(this.value, {super.key});
  final String value;

  @override
  State<SensitiveText> createState() => _SensitiveTextState();
}

class _SensitiveTextState extends State<SensitiveText> {
  bool _revealed = false;

  Future<void> _toggle() async {
    setState(() => _revealed = !_revealed);
    if (!_revealed ||
        !await SensitiveInfoService.instance.consumeFirstRevealHint()) {
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Want these always visible?'),
        content: const Text(
          'Account and license details are hidden by default so you can '
          'record or share your screen safely. In Settings > General you can '
          'turn on "Show account & license details" to always show them.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SensitiveInfoService.instance,
      builder: (context, _) {
        final always = SensitiveInfoService.instance.visible;
        return Row(
          children: [
            Flexible(
              child: Text(
                always || _revealed ? widget.value : SensitiveInfoService.mask,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            if (!always)
              IconButton(
                onPressed: _toggle,
                tooltip: _revealed ? 'Hide' : 'Show',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(_revealed
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
              ),
          ],
        );
      },
    );
  }
}
