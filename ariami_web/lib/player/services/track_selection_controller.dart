import 'package:flutter/foundation.dart';

/// Multi-select state for a track list.
///
/// Two ways in, both Spotify's: cmd/ctrl-click or shift-click any row starts
/// selecting straight away, or the Select button turns the mode on first. An
/// unmodified click outside the mode still does nothing, so every existing row
/// interaction (double-click to play, drag onto a sidebar playlist,
/// right-click menu) keeps working untouched. Ids are held rather than tracks
/// so a library reload can't resurrect a stale copy of a row — the view
/// re-resolves them each build.
class TrackSelectionController extends ChangeNotifier {
  final Set<String> _ids = <String>{};
  bool _active = false;

  /// Index of the last plainly-clicked row, used as the origin of a
  /// shift-click range. Null when the anchor no longer means anything.
  int? _anchor;

  bool get active => _active;
  int get count => _ids.length;
  bool get isEmpty => _ids.isEmpty;
  Set<String> get selectedIds => Set<String>.unmodifiable(_ids);
  bool isSelected(String id) => _ids.contains(id);

  void enter() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void exit() {
    if (!_active && _ids.isEmpty) return;
    _active = false;
    _ids.clear();
    _anchor = null;
    notifyListeners();
  }

  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    _anchor = null;
    notifyListeners();
  }

  /// Routes a click on row [index] of the currently visible list.
  ///
  /// Outside selection mode a modifier turns it on and applies the click in
  /// one go; an unmodified click is left alone for the row's own gestures.
  /// Returns whether the click was consumed as a selection.
  bool handleRowTap(
    List<String> visibleIds,
    int index, {
    required bool shift,
    required bool meta,
  }) {
    if (index < 0 || index >= visibleIds.length) return false;
    if (!_active) {
      if (!shift && !meta) return false;
      _active = true;
    }
    if (shift) {
      selectRange(visibleIds, index);
    } else {
      toggle(visibleIds[index], index: index);
    }
    return true;
  }

  void toggle(String id, {int? index}) {
    if (!_ids.remove(id)) _ids.add(id);
    _anchor = index;
    notifyListeners();
  }

  /// Selects every row between the anchor and [index] inclusive, keeping
  /// whatever was already selected. Falls back to a plain toggle when there is
  /// no anchor yet (a shift-click as the very first click).
  void selectRange(List<String> visibleIds, int index) {
    final anchor = _anchor;
    if (anchor == null || anchor >= visibleIds.length) {
      toggle(visibleIds[index], index: index);
      return;
    }
    final from = anchor < index ? anchor : index;
    final to = anchor < index ? index : anchor;
    _ids.addAll(visibleIds.sublist(from, to + 1));
    notifyListeners();
  }

  void selectAll(List<String> visibleIds) {
    _ids.addAll(visibleIds);
    _anchor = null;
    notifyListeners();
  }
}
