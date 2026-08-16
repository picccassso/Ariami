import 'package:flutter/material.dart';

import '../ui/status_pill.dart';

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
    return NoticeBanner(
      icon: Icons.lock_outline_rounded,
      tone: StatusTone.caution,
      message: message,
      action: OutlinedButton(
        onPressed: onSignInAsOwner,
        child: const Text('Sign in as owner'),
      ),
    );
  }
}
