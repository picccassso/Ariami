import 'package:ariami_core/models/image_limits.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_models.dart';
import '../services/connection_controller.dart';
import '../services/library_controller.dart';
import '../services/player_host.dart';
import 'playlist_artwork.dart';

/// Prompts for a name and creates a new (client-owned) playlist, optionally
/// seeded with [initialSongIds]. Returns the new playlist's id, or null if the
/// user cancelled or creation failed.
Future<String?> showCreatePlaylistDialog(
  BuildContext context, {
  List<String> initialSongIds = const <String>[],
}) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('New playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) {
          if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isNotEmpty) Navigator.pop(dialogContext, value);
          },
          child: const Text('Create'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null || !context.mounted) return null;
  return context.read<LibraryController>().createPlaylist(
        name,
        initialSongIds: initialSongIds,
      );
}

/// Opens the single playlist-details surface used for both its title and
/// artwork. Photo changes live behind the cover's edit affordance, rather than
/// taking up separate rows in every playlist menu.
Future<void> showEditPlaylistDetailsDialog(
  BuildContext context,
  PlaylistSummary playlist,
) async {
  final library = context.read<LibraryController>();
  final connection = context.read<ConnectionController>();
  await showDialog<void>(
    context: context,
    builder: (_) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryController>.value(value: library),
        ChangeNotifierProvider<ConnectionController>.value(
          value: connection,
        ),
      ],
      child: _EditPlaylistDetailsDialog(playlist: playlist),
    ),
  );
}

enum _PlaylistPhotoAction { change, remove }

class _EditPlaylistDetailsDialog extends StatefulWidget {
  const _EditPlaylistDetailsDialog({required this.playlist});

  final PlaylistSummary playlist;

  @override
  State<_EditPlaylistDetailsDialog> createState() =>
      _EditPlaylistDetailsDialogState();
}

class _EditPlaylistDetailsDialogState
    extends State<_EditPlaylistDetailsDialog> {
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editPhoto(_PlaylistPhotoAction action) async {
    switch (action) {
      case _PlaylistPhotoAction.change:
        await pickAndUploadPlaylistPhoto(context, widget.playlist);
        break;
      case _PlaylistPhotoAction.remove:
        await removePlaylistPhoto(context, widget.playlist);
        break;
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() => _saving = true);
    try {
      if (name != widget.playlist.name) {
        await context.read<LibraryController>().renamePlaylist(
              widget.playlist.id,
              name,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomPhoto =
        context.watch<LibraryController>().playlistImageVersion(
                  widget.playlist.id,
                ) !=
            null;

    return AlertDialog(
      title: const Text('Edit details'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PopupMenuButton<_PlaylistPhotoAction>(
              tooltip: 'Edit playlist photo',
              onSelected: _editPhoto,
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistPhotoAction.change,
                  child: Text('Change photo'),
                ),
                if (hasCustomPhoto)
                  const PopupMenuItem(
                    value: _PlaylistPhotoAction.remove,
                    child: Text('Remove photo'),
                  ),
              ],
              child: Stack(
                children: [
                  PlaylistArtwork(
                    playlist: widget.playlist,
                    size: 164,
                    borderRadius: 6,
                  ),
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      radius: 18,
                      child: Icon(Icons.edit_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: TextField(
                controller: _nameController,
                autofocus: true,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Playlist name'),
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}

/// Lets the user pick a JPEG/PNG/WebP photo and uploads it as [playlist]'s
/// custom cover. The server syncs it to every signed-in client (mobile,
/// desktop, TV) through the account's playlist-image store.
Future<void> pickAndUploadPlaylistPhoto(
  BuildContext context,
  PlaylistSummary playlist,
) async {
  final library = context.read<LibraryController>();
  final readLocalFileBytes = maybeReadHost(context)?.readLocalFileBytes;
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Choose playlist photo',
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  if (file == null) return;

  var bytes = file.bytes;
  if (bytes == null && file.path != null && readLocalFileBytes != null) {
    try {
      bytes = await readLocalFileBytes(file.path!);
    } catch (_) {
      bytes = null;
    }
  }
  if (!context.mounted) return;
  if (bytes == null || bytes.isEmpty) {
    _toast(context, 'Could not read that file.');
    return;
  }
  if (bytes.length > kMaxUserImageBytes) {
    _toast(context, 'Photo is too large (max 5 MB).');
    return;
  }
  final contentType = _sniffPlaylistImageContentType(bytes);
  if (contentType == null) {
    _toast(context, 'Unsupported image format. Use JPEG, PNG or WebP.');
    return;
  }

  try {
    await library.setPlaylistImage(
      playlist.id,
      bytes: bytes,
      contentType: contentType,
    );
    if (context.mounted) _toast(context, 'Playlist photo updated');
  } catch (_) {
    if (context.mounted) _toast(context, 'Could not upload the photo.');
  }
}

/// Removes [playlist]'s custom cover photo from the account's image store,
/// reverting every client back to the song-artwork mosaic.
Future<void> removePlaylistPhoto(
  BuildContext context,
  PlaylistSummary playlist,
) async {
  final library = context.read<LibraryController>();
  try {
    await library.removePlaylistImage(playlist.id);
    if (context.mounted) _toast(context, 'Playlist photo removed');
  } catch (_) {
    if (context.mounted) _toast(context, 'Could not remove the photo.');
  }
}

/// Maps image bytes to the content types the server accepts (mirrors the
/// mobile client's sniffing), or null for anything else.
String? _sniffPlaylistImageContentType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDeletePlaylist(
  BuildContext context,
  PlaylistSummary playlist,
) async {
  final isCreated =
      context.read<LibraryController>().isCreatedPlaylist(playlist.id);
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete playlist?'),
          content: Text(
            isCreated
                ? '“${playlist.name}” will be permanently deleted.'
                : '“${playlist.name}” will be removed from this desktop '
                    'library. The source playlist file on the server will not '
                    'be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;
  await context.read<LibraryController>().deletePlaylist(playlist.id);
  return true;
}
