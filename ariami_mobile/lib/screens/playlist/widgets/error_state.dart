import 'package:flutter/material.dart';

class ErrorState extends StatelessWidget {
  final String message;

  final VoidCallback? onRetry;

  /// Larger, centered message with more spacing before the retry button.
  final bool roomy;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.roomy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: roomy ? 16 : null,
              color: Colors.grey[600],
            ),
            textAlign: roomy ? TextAlign.center : null,
          ),
          SizedBox(height: roomy ? 24 : 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
