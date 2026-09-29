import 'package:flutter/material.dart';

/// Result of [showAliasDialog]: the new alias, or null to clear it.
class AliasEditResult {
  const AliasEditResult(this.alias);

  final String? alias;
}

/// Longest alias the server accepts (see
/// `AriamiHttpServer.normalizeEndpointAlias`).
const int kMaxEndpointAliasLength = 40;

/// Asks for a display name for a server address. Returns null when cancelled;
/// an [AliasEditResult] with a null alias means "remove the alias".
Future<AliasEditResult?> showAliasDialog(
  BuildContext context, {
  required String title,
  required String address,
  String? currentAlias,
}) {
  final controller = TextEditingController(text: currentAlias ?? '');

  return showDialog<AliasEditResult?>(
    context: context,
    builder: (dialogContext) {
      void save() {
        final trimmed = controller.text.trim();
        Navigator.of(dialogContext)
            .pop(AliasEditResult(trimmed.isEmpty ? null : trimmed));
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shown in place of $address on the dashboard and in the '
                'apps. The address itself does not change.',
                style: TextStyle(
                  color: Theme.of(dialogContext)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: kMaxEndpointAliasLength,
                decoration: const InputDecoration(labelText: 'Alias'),
                onSubmitted: (_) => save(),
              ),
            ],
          ),
        ),
        actions: [
          if (currentAlias != null && currentAlias.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const AliasEditResult(null)),
              child: const Text('Remove alias'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(onPressed: save, child: const Text('Save')),
        ],
      );
    },
  ).whenComplete(controller.dispose);
}
