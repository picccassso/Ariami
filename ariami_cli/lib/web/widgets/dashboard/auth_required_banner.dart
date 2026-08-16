import 'package:flutter/material.dart';

import '../ui/status_pill.dart';

class AuthRequiredBanner extends StatelessWidget {
  const AuthRequiredBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const NoticeBanner(
      icon: Icons.verified_user_rounded,
      tone: StatusTone.positive,
      message: 'Sign-in is required on this server. '
          'Everyone connecting needs an account.',
    );
  }
}
