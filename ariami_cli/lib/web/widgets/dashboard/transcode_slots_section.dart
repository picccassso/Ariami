import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import 'transcode_slots_dialog.dart';

class TranscodeSlotsSection extends StatelessWidget {
  const TranscodeSlotsSection({
    super.key,
    required this.snapshot,
    required this.isLoading,
    required this.onEdit,
    this.error,
  });

  final TranscodeSlotsSnapshot? snapshot;
  final bool isLoading;
  final VoidCallback onEdit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CONFIGURATION',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlack,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderGrey),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.speed_rounded, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRANSCODE SLOTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else if (error != null)
                      Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (snapshot != null) ...[
                      Text(
                        formatTranscodeSlotsDisplay(snapshot!),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (snapshot!.isCustom) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Default for this device: ${snapshot!.defaultSlots}',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ] else
                      const Text(
                        'Unavailable',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: isLoading || snapshot == null ? null : onEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.borderGrey),
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
