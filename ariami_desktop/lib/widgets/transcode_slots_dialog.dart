import 'package:ariami_core/services/transcoding/transcode_slots_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

String formatTranscodeSlotsDisplay(TranscodeSlotsSnapshot snapshot) {
  if (snapshot.isCustom) {
    return '${snapshot.effective}';
  }
  return '${snapshot.effective} (default)';
}

class TranscodeSlotsEditResult {
  const TranscodeSlotsEditResult.save(this.slots) : reset = false;

  const TranscodeSlotsEditResult.reset() : slots = null, reset = true;

  final int? slots;
  final bool reset;
}

Future<TranscodeSlotsEditResult?> showTranscodeSlotsDialog(
  BuildContext context, {
  required TranscodeSlotsSnapshot snapshot,
}) async {
  final controller = TextEditingController(text: snapshot.effective.toString());
  String? dialogError;

  final result = await showDialog<TranscodeSlotsEditResult?>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Transcode Slots'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controls how many Sonic transcodes can run at once.',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Transcode slots',
                      helperText:
                          'Default for this device: ${snapshot.defaultSlots}',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        dialogError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (snapshot.isCustom)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext)
                      .pop(const TranscodeSlotsEditResult.reset()),
                  child: const Text('Reset to default'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsed = int.tryParse(controller.text.trim());
                  if (parsed == null) {
                    setDialogState(() {
                      dialogError = 'Enter a valid number of slots.';
                    });
                    return;
                  }

                  try {
                    TranscodeSlotsPolicy.validateSlots(parsed);
                  } catch (e) {
                    setDialogState(() {
                      dialogError = e.toString();
                    });
                    return;
                  }

                  Navigator.of(dialogContext)
                      .pop(TranscodeSlotsEditResult.save(parsed));
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );

  controller.dispose();
  return result;
}
