import 'package:flutter/material.dart';

/// Inline error for owner-only dashboard sections with sign-in CTA.
class OwnerAccessErrorPanel extends StatelessWidget {
  const OwnerAccessErrorPanel({
    super.key,
    required this.message,
    required this.onSignInAsOwner,
  });

  final String message;
  final VoidCallback onSignInAsOwner;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onSignInAsOwner,
            child: const Text('SIGN IN AS OWNER'),
          ),
        ],
      ),
    );
  }
}
