import 'track_selection_controller.dart';

/// Multi-select state for the library sidebar, keyed `type:targetId` (the same
/// keys the hidden-items API uses) rather than by song id.
///
/// The interaction is identical to a track list's — cmd/ctrl-click or
/// shift-click starts selecting, an unmodified click is left alone so opening
/// a collection still works — so this subclasses [TrackSelectionController] to
/// reuse those semantics while staying a distinct type for `Provider` lookup.
/// The sidebar and the track lists select independently.
class SidebarSelectionController extends TrackSelectionController {
  /// The keys the sidebar is currently listing, in display order.
  ///
  /// The sidebar republishes this on every build (a plain assignment — a
  /// notification here would loop through that same build), which is what lets
  /// the floating bar, which lives outside the sidebar, offer Select all and
  /// report the selection in the order the user sees it.
  List<String> visibleKeys = const <String>[];

  /// The current selection in sidebar order, with anything no longer listed
  /// (hidden, filtered out, or scrolled out of a search) kept at the end so a
  /// batch action never silently drops part of what was selected.
  List<String> get orderedSelection {
    final selected = selectedIds;
    return <String>[
      for (final key in visibleKeys)
        if (selected.contains(key)) key,
      for (final key in selected)
        if (!visibleKeys.contains(key)) key,
    ];
  }
}
