/// Whether [value] is a storable song attribute: a bool, a number or a list
/// of strings. Null is not a value; it is how a write removes a key.
bool isValidSongAttributeValue(Object? value) =>
    value is bool ||
    value is num ||
    (value is List && value.every((item) => item is String));

typedef _Condition = bool Function(
  String songId,
  Map<String, Object> attributes,
  Map<String, Set<String>> playlistSongIds,
);

/// A parsed `POST /api/v2/songs/query` filter and sort.
///
/// Every `where` condition must match. Attribute conditions only match songs
/// that carry the attribute, except `exists: false`. Playlist conditions are
/// resolved by the caller into [playlistIds] -> song ids.
class SongAttributeQuery {
  SongAttributeQuery._(this._conditions, this._sort, this.playlistIds);

  final List<_Condition> _conditions;
  final List<({String attr, bool descending})> _sort;

  /// Playlists referenced by `inPlaylist` / `notInPlaylist` conditions.
  final Set<String> playlistIds;

  /// Throws [FormatException] describing the first invalid part.
  factory SongAttributeQuery.parse({Object? where, Object? sort}) {
    final conditions = <_Condition>[];
    final playlistIds = <String>{};
    if (where is! List?) throw const FormatException('where must be a list');
    for (final raw in where ?? const <Object?>[]) {
      if (raw is! Map) {
        throw const FormatException('conditions must be objects');
      }
      conditions.add(_parseCondition(raw, playlistIds));
    }

    final sortKeys = <({String attr, bool descending})>[];
    if (sort is! List?) throw const FormatException('sort must be a list');
    for (final raw in sort ?? const <Object?>[]) {
      final attr = raw is Map ? raw['attr'] : null;
      final dir = raw is Map ? raw['dir'] ?? 'asc' : null;
      if (attr is! String || (dir != 'asc' && dir != 'desc')) {
        throw const FormatException(
            'sort entries need an attr and dir "asc" or "desc"');
      }
      sortKeys.add((attr: attr, descending: dir == 'desc'));
    }
    return SongAttributeQuery._(conditions, sortKeys, playlistIds);
  }

  bool matches(
    String songId,
    Map<String, Object> attributes,
    Map<String, Set<String>> playlistSongIds,
  ) =>
      _conditions
          .every((condition) => condition(songId, attributes, playlistSongIds));

  /// Orders by the sort keys, songs missing a key last in either direction.
  /// Bools sort false before true. Returns 0 on a full tie.
  int compare(Map<String, Object> a, Map<String, Object> b) {
    for (final key in _sort) {
      final left = _sortable(a[key.attr]);
      final right = _sortable(b[key.attr]);
      if (left == null && right == null) continue;
      if (left == null) return 1;
      if (right == null) return -1;
      final order = left.compareTo(right);
      if (order != 0) return key.descending ? -order : order;
    }
    return 0;
  }

  static num? _sortable(Object? value) => value is num
      ? value
      : value is bool
          ? (value ? 1 : 0)
          : null;

  static _Condition _parseCondition(Map raw, Set<String> playlistIds) {
    for (final op in const ['inPlaylist', 'notInPlaylist']) {
      if (!raw.containsKey(op)) continue;
      final playlistId = raw[op];
      if (raw.length != 1 || playlistId is! String || playlistId.isEmpty) {
        throw FormatException('$op takes a playlist id and nothing else');
      }
      playlistIds.add(playlistId);
      final wanted = op == 'inPlaylist';
      return (songId, _, playlists) =>
          (playlists[playlistId]?.contains(songId) ?? false) == wanted;
    }

    final attr = raw['attr'];
    if (attr is! String || raw.length < 2) {
      throw const FormatException('conditions need an attr and an operator');
    }
    final tests = <bool Function(Object? value)>[
      for (final entry in raw.entries)
        if (entry.key != 'attr') _parseOperator('${entry.key}', entry.value),
    ];
    return (_, attributes, __) => tests.every((test) => test(attributes[attr]));
  }

  static bool Function(Object? value) _parseOperator(
    String op,
    Object? operand,
  ) {
    switch (op) {
      case 'eq' || 'ne' when operand is bool || operand is num:
        final wanted = op == 'eq';
        return (value) => value != null && (value == operand) == wanted;
      case 'gt' || 'gte' || 'lt' || 'lte' when operand is num:
        return (value) =>
            value is num &&
            switch (op) {
              'gt' => value > operand,
              'gte' => value >= operand,
              'lt' => value < operand,
              _ => value <= operand,
            };
      case 'contains' when operand is String:
        return (value) => value is List && value.contains(operand);
      case 'containsAny'
          when operand is List && operand.every((item) => item is String):
        return (value) => value is List && value.any(operand.contains);
      case 'exists' when operand is bool:
        return (value) => (value != null) == operand;
    }
    throw FormatException('unsupported operator or operand: $op');
  }
}
