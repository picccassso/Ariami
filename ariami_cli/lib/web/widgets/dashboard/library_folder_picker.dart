import 'package:flutter/material.dart';

import '../../utils/constants.dart';

/// A browsable tree of the library's folders, with the library root on top.
/// Tapping a row selects it; the chevron expands or collapses it.
class LibraryFolderPicker extends StatefulWidget {
  const LibraryFolderPicker({
    super.key,
    required this.folders,
    required this.selected,
    required this.onSelected,
  });

  /// `/`-separated paths relative to the library root.
  final List<String> folders;

  /// The selected folder; empty is the library root.
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  State<LibraryFolderPicker> createState() => _LibraryFolderPickerState();
}

class _LibraryFolderPickerState extends State<LibraryFolderPicker> {
  final Set<String> _expanded = {};

  static String _parentOf(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  @override
  void initState() {
    super.initState();
    _expandAncestorsOf(widget.selected);
  }

  @override
  void didUpdateWidget(LibraryFolderPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _expandAncestorsOf(widget.selected);
  }

  /// Keeps the selection visible, e.g. after a new folder is added.
  void _expandAncestorsOf(String path) {
    for (var parent = _parentOf(path);
        parent.isNotEmpty;
        parent = _parentOf(parent)) {
      _expanded.add(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <String, List<String>>{};
    for (final folder in widget.folders) {
      children.putIfAbsent(_parentOf(folder), () => []).add(folder);
    }
    final rows = <(String, int)>[('', 0)];
    void addVisible(String parent, int depth) {
      for (final folder in children[parent] ?? const <String>[]) {
        rows.add((folder, depth));
        if (_expanded.contains(folder)) addVisible(folder, depth + 1);
      }
    }

    addVisible('', 1);

    return Container(
      height: 240,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.borderStrong),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final (folder, depth) = rows[index];
          final hasChildren = children.containsKey(folder) && folder.isNotEmpty;
          final isExpanded = _expanded.contains(folder);
          final isSelected = folder == widget.selected;
          return Material(
            color: isSelected ? AppTheme.surfaceHover : Colors.transparent,
            child: InkWell(
              onTap: () => widget.onSelected(folder),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.0 + depth * 18, 6, 12, 6),
                // A fixed height so rows with and without a chevron match.
                child: SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 28,
                        child: hasChildren
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 20,
                                constraints: const BoxConstraints.tightFor(
                                    width: 28, height: 24),
                                icon: Icon(isExpanded
                                    ? Icons.expand_more_rounded
                                    : Icons.chevron_right_rounded),
                                onPressed: () => setState(() => isExpanded
                                    ? _expanded.remove(folder)
                                    : _expanded.add(folder)),
                              )
                            : null,
                      ),
                      Icon(
                        folder.isEmpty
                            ? Icons.library_music_rounded
                            : Icons.folder_rounded,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          folder.isEmpty
                              ? 'Library root'
                              : folder.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_rounded,
                            size: 18, color: AppTheme.success),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
