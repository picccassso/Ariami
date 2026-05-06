import 'dart:async';

import 'package:flutter/material.dart';

import 'mini_player_aware_bottom_sheet.dart';

OverlayEntry? _queueConfirmationEntry;
Timer? _queueConfirmationTimer;

void showQueueActionConfirmation(
  BuildContext context, {
  String message = 'Added to queue',
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  _queueConfirmationTimer?.cancel();
  _queueConfirmationEntry?.remove();

  _queueConfirmationEntry = OverlayEntry(
    builder: (context) => _QueueActionConfirmation(
      key: UniqueKey(),
      message: message,
    ),
  );
  overlay.insert(_queueConfirmationEntry!);

  _queueConfirmationTimer = Timer(const Duration(seconds: 3), () {
    _queueConfirmationEntry?.remove();
    _queueConfirmationEntry = null;
  });
}

class _QueueActionConfirmation extends StatefulWidget {
  final String message;

  const _QueueActionConfirmation({
    super.key,
    required this.message,
  });

  @override
  State<_QueueActionConfirmation> createState() =>
      _QueueActionConfirmationState();
}

class _QueueActionConfirmationState extends State<_QueueActionConfirmation> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isVisible = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = getMiniPlayerAwareBottomPadding(context) + 16;

    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: _isVisible ? Offset.zero : const Offset(0, 1.2),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _isVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Material(
              color: colorScheme.onSurface,
              borderRadius: BorderRadius.circular(6),
              elevation: 8,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  widget.message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.surface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
