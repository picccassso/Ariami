import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// What the owner chose in [ResetAriamiDialog].
enum ResetChoice { setupOnly, factory }

/// Two-step confirmation for resetting the server: pick a scope, then type
/// RESET. Mirrors the `ariami_cli reset` command's prompts, because this
/// clears the same state and cannot be undone.
class ResetAriamiDialog extends StatefulWidget {
  const ResetAriamiDialog({super.key});

  static const String confirmationWord = 'RESET';

  @override
  State<ResetAriamiDialog> createState() => _ResetAriamiDialogState();
}

class _ResetAriamiDialogState extends State<ResetAriamiDialog> {
  final TextEditingController _confirmController = TextEditingController();

  ResetChoice _choice = ResetChoice.setupOnly;
  bool _isSubmitting = false;

  bool get _isConfirmed =>
      _confirmController.text.trim() == ResetAriamiDialog.confirmationWord;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_isConfirmed || _isSubmitting) return;
    setState(() => _isSubmitting = true);
    Navigator.of(context).pop(_choice);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset Ariami'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your music files are never deleted. The server stops once '
                'the reset finishes — start it again from the machine.',
                style: AppTheme.meta,
              ),
              const SizedBox(height: 18),
              _ScopeOption(
                value: ResetChoice.setupOnly,
                groupValue: _choice,
                onChanged: _isSubmitting
                    ? null
                    : (value) => setState(() => _choice = value),
                title: 'Setup and config only',
                description: 'Keeps your library database and accounts. '
                    'Ariami asks you to set it up again on next start.',
              ),
              const SizedBox(height: 10),
              _ScopeOption(
                value: ResetChoice.factory,
                groupValue: _choice,
                onChanged: _isSubmitting
                    ? null
                    : (value) => setState(() => _choice = value),
                title: 'Factory reset',
                description: 'Removes every account, session, cache and the '
                    'library database as well. Your library is rescanned from '
                    'scratch afterwards.',
                destructive: true,
              ),
              const SizedBox(height: 20),
              Text(
                'Type ${ResetAriamiDialog.confirmationWord} to confirm',
                style: AppTheme.fieldLabel,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _confirmController,
                autofocus: true,
                enabled: !_isSubmitting,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: ResetAriamiDialog.confirmationWord,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isConfirmed && !_isSubmitting ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: AppTheme.pureBlack,
          ),
          child: Text(
            _choice == ResetChoice.factory
                ? 'Factory reset'
                : 'Reset setup',
          ),
        ),
      ],
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.title,
    required this.description,
    this.destructive = false,
  });

  final ResetChoice value;
  final ResetChoice groupValue;
  final ValueChanged<ResetChoice>? onChanged;
  final String title;
  final String description;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final accent = destructive ? AppTheme.danger : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.6)
                  : AppTheme.borderGrey,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 19,
                color: selected ? accent : AppTheme.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(description, style: AppTheme.meta),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
