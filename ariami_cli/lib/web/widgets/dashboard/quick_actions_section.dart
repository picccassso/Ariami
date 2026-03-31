import 'package:flutter/material.dart';

import '../../utils/constants.dart';

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.isScanning,
    required this.onRescanLibrary,
    required this.onViewQRCode,
  });

  final bool isScanning;
  final VoidCallback onRescanLibrary;
  final VoidCallback onViewQRCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK ACTIONS',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppTheme.textSecondary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: isScanning ? null : onRescanLibrary,
                icon: isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(isScanning ? 'SCANNING...' : 'RESCAN LIBRARY'),
              ),
            ),
            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: onViewQRCode,
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('SHOW QR CODE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceBlack,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.borderGrey),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
