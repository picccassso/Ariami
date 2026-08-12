import 'package:ariami_core/services/recommendations/music_recommendation_models.dart';
import 'package:flutter/material.dart';

import '../../../../widgets/library/genre_label.dart';
import '../library_state.dart';

class GenreFilterBar extends StatefulWidget {
  const GenreFilterBar({
    super.key,
    required this.state,
    required this.onChanged,
  });

  final LibraryState state;
  final ValueChanged<String?> onChanged;

  @override
  State<GenreFilterBar> createState() => _GenreFilterBarState();
}

class _GenreFilterBarState extends State<GenreFilterBar> {
  static const _collapsedLimit = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final genres = widget.state.genreIndex.genres;
    if (genres.isEmpty) return const SizedBox.shrink();

    final selected = widget.state.genreFilter;
    final visible = visibleGenreFacets(
      genres,
      selected,
      limit: _collapsedLimit,
      expanded: _expanded,
    );
    final hidden = genres.length - _collapsedLimit;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _GenreChip(
            label: 'All',
            selected: selected == null,
            onTap: () => widget.onChanged(null),
          ),
          for (final genre in visible) ...[
            const SizedBox(width: 8),
            _GenreChip(
              label: '${musicDiscoveryTagLabel(genre)} '
                  '(${widget.state.genreAlbumCount(genre)})',
              selected: selected == genre,
              onTap: () => widget.onChanged(selected == genre ? null : genre),
            ),
          ],
          if (hidden > 0) ...[
            const SizedBox(width: 8),
            _GenreChip(
              label: _expanded ? 'Show less' : '+$hidden more',
              selected: false,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ],
      ),
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}
