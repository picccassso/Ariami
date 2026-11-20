import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../services/theme_controller.dart';
import '../../theme/player_theme.dart';
import 'settings_widgets.dart';

/// Inline, live custom-colour picker: a preview chip, quick preset swatches and
/// a full HSV area with a hex field. Every change is applied to the theme
/// immediately so the whole app recolours as you pick — no modal, no "Save".
///
/// The embedded [ColorPicker] re-seeds itself from its `pickerColor` on every
/// rebuild, which would make it jump while dragging once we apply live. To keep
/// it smooth we leave the picker *uncontrolled*: its seed (and [ValueKey]) only
/// changes for colour changes that come from outside the picker (e.g. tapping a
/// preset swatch), never from its own drag callbacks.
class CustomColorControl extends StatefulWidget {
  const CustomColorControl({
    super.key,
    required this.color,
    required this.onChanged,
  });
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<CustomColorControl> createState() => _CustomColorControlState();
}

class _CustomColorControlState extends State<CustomColorControl> {
  late Color _seed = widget.color; // what the picker is seeded with
  late Color _current = widget.color; // latest value, drives the preview
  Color? _lastEmitted; // last colour we pushed up, to detect external changes

  // The picker widget is cached and only rebuilt when [_seed] changes. Live
  // updates rebuild this control (and the watching ancestor) on every drag
  // frame; returning the *same* picker instance makes the framework skip the
  // ColorPicker's didUpdateWidget — which otherwise resets its internal HSV to
  // [pickerColor] and would snap the cursor back mid-drag.
  late Widget _picker = _buildPicker();

  @override
  void didUpdateWidget(CustomColorControl old) {
    super.didUpdateWidget(old);
    // Only re-seed the picker when the colour changed from outside this control
    // (a preset tap, a load from prefs). Our own live updates come back as
    // [widget.color] == [_lastEmitted] and must not disturb the active drag.
    if (widget.color != _lastEmitted && widget.color != _current) {
      _seedTo(widget.color, notify: false);
    }
  }

  void _emit(Color color) {
    _lastEmitted = color;
    setState(() => _current = color);
    widget.onChanged(color);
  }

  /// Re-seeds the picker (rebuilding it) — used for external jumps such as a
  /// preset swatch tap or an external colour change.
  void _seedTo(Color color, {bool notify = true}) {
    _lastEmitted = color;
    setState(() {
      _seed = color;
      _current = color;
      _picker = _buildPicker();
    });
    if (notify) widget.onChanged(color);
  }

  Widget _buildPicker() {
    return ConstrainedBox(
      // Constrain so the fixed-width picker never overflows a narrow panel.
      constraints: const BoxConstraints(maxWidth: 320),
      child: ColorPicker(
        key: ValueKey<int>(_seed.toARGB32()),
        pickerColor: _seed,
        onColorChanged: _emit,
        enableAlpha: false,
        displayThumbColor: true,
        paletteType: PaletteType.hsvWithHue,
        labelTypes: const [],
        portraitOnly: true,
        colorPickerWidth: 320,
        pickerAreaHeightPercent: 0.7,
        pickerAreaBorderRadius: BorderRadius.circular(PlayerTheme.tileRadius),
        hexInputBar: true,
      ),
    );
  }

  String get _hex =>
      '#${(_current.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _current,
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.border, width: 2),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Custom accent',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(_hex,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in ThemeController.presetSwatches)
              ColorSwatchButton(
                color: color,
                selected: _current.toARGB32() == color.toARGB32(),
                onTap: () => _seedTo(color),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _picker,
      ],
    );
  }
}
