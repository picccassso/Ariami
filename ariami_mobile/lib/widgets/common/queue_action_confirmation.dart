import 'dart:async';

import 'package:flutter/material.dart';

import 'mini_player_aware_bottom_sheet.dart';

OverlayEntry? _queueConfirmationEntry;
Timer? _queueConfirmationTimer;

void _dismissQueueConfirmation() {
  _queueConfirmationTimer?.cancel();
  _queueConfirmationTimer = null;
  _queueConfirmationEntry?.remove();
  _queueConfirmationEntry = null;
}

void showQueueActionConfirmation(
  BuildContext context, {
  String message = 'Added to queue',
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  _dismissQueueConfirmation();

  _queueConfirmationEntry = OverlayEntry(
    builder: (context) => _QueueActionConfirmation(
      key: UniqueKey(),
      message: message,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              _dismissQueueConfirmation();
              onAction();
            },
    ),
  );
  overlay.insert(_queueConfirmationEntry!);

  _queueConfirmationTimer = Timer(duration, _dismissQueueConfirmation);
}

class _QueueActionConfirmation extends StatefulWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _QueueActionConfirmation({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
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
    final hasAction =
        widget.actionLabel != null && widget.onAction != null;

    final bar = Material(
      color: colorScheme.onSurface,
      borderRadius: BorderRadius.circular(6),
      elevation: 8,
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Text(
                widget.message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.surface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          if (hasAction)
            InkWell(
              onTap: widget.onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  widget.actionLabel!.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                ),
              ),
            ),
        ],
      ),
    );

    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: AnimatedSlide(
        offset: _isVisible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: hasAction ? bar : IgnorePointer(child: bar),
        ),
      ),
    );
  }
}
