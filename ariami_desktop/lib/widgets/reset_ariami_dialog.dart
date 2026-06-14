import 'package:ariami_core/ariami_core.dart';
import 'package:flutter/material.dart';

/// Shows the "Reset Ariami" dialog. Returns the chosen [ResetScope], or null if
/// the user cancelled.
Future<ResetScope?> showResetAriamiDialog(BuildContext context) {
  return showDialog<ResetScope>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ResetAriamiDialog(),
  );
}

class _ResetAriamiDialog extends StatefulWidget {
  const _ResetAriamiDialog();

  @override
  State<_ResetAriamiDialog> createState() => _ResetAriamiDialogState();
}

class _ResetAriamiDialogState extends State<_ResetAriamiDialog> {
  static const _confirmationWord = 'RESET';

  ResetScope _scope = ResetScope.setupOnly;
  final TextEditingController _confirmController = TextEditingController();
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _confirmController.addListener(() {
      final confirmed = _confirmController.text.trim() == _confirmationWord;
      if (confirmed != _confirmed) {
        setState(() => _confirmed = confirmed);
      }
    });
  }

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Ariami'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ResetOptionCard(
                title: 'Reset setup only',
                description:
                    'Clears server config, pairing state, remembered '
                    'addresses, and setup progress. Keeps your music files.',
                selected: _scope == ResetScope.setupOnly,
                onTap: () => setState(() => _scope = ResetScope.setupOnly),
              ),
              const SizedBox(height: 12),
              _ResetOptionCard(
                title: 'Factory reset Ariami',
                description:
                    'Clears Ariami database, users, sessions, stats, '
                    'playlists, cache, and setup state. Keeps your original '
                    'music files.',
                selected: _scope == ResetScope.factoryReset,
                onTap: () => setState(() => _scope = ResetScope.factoryReset),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Ariami will never delete your music folder.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Type RESET to continue'),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'RESET',
                ),
                onSubmitted: (_) {
                  if (_confirmed) Navigator.of(context).pop(_scope);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: _confirmed ? () => Navigator.of(context).pop(_scope) : null,
          child: const Text('Reset'),
        ),
      ],
    );
  }
}

class _ResetOptionCard extends StatelessWidget {
  const _ResetOptionCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.5),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
