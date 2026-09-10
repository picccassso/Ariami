/// Music storage health is independent of whether the HTTP server is online.
/// Unknown keeps clients compatible with servers predating this field.
enum MusicAvailability {
  unknown,
  checking,
  ready,
  unavailable,
  empty,
  scanFailed;

  bool get needsAttention =>
      this == unavailable || this == empty || this == scanFailed;

  String get title => switch (this) {
        unavailable => 'Server online · Music unavailable',
        empty => 'Server online · No music found',
        scanFailed => 'Server online · Library scan failed',
        checking => 'Server online · Checking music',
        ready => 'Music ready',
        unknown => 'Server online',
      };

  String get message => switch (this) {
        unavailable => 'Ariami is reachable, but cannot access its music. '
            'Check that the server’s NAS or drive is mounted and readable. '
            'Ariami will retry automatically.',
        empty => 'No audio files were found in the server’s music folder. '
            'If you expected music, check the folder and NAS or drive mount. '
            'Ariami will retry automatically.',
        scanFailed => 'Ariami could not finish scanning the music folder. '
            'Your saved library has been kept. Check the server dashboard. '
            'Ariami will retry automatically.',
        checking => 'Ariami is checking the server’s music folder.',
        _ => '',
      };

  Map<String, dynamic> toJson() => {'status': name};

  static MusicAvailability fromJson(Object? json) {
    final status = json is Map ? json['status'] : null;
    return values.firstWhere((value) => value.name == status,
        orElse: () => unknown);
  }
}
