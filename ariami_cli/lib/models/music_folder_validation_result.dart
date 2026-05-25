/// Result of validating or saving a music folder path via the setup API.
class MusicFolderValidationResult {
  const MusicFolderValidationResult({
    required this.isValid,
    required this.path,
    this.error,
    this.message,
  });

  final bool isValid;
  final String path;
  final String? error;
  final String? message;

  factory MusicFolderValidationResult.fromJson(Map<String, dynamic> json) {
    final validation = json['validation'] as Map<String, dynamic>? ?? json;
    final path = validation['path'] as String? ??
        json['path'] as String? ??
        '';

    return MusicFolderValidationResult(
      isValid: json['success'] as bool? ??
          validation['isValid'] as bool? ??
          false,
      path: path,
      error: validation['error'] as String? ?? json['error'] as String?,
      message: validation['message'] as String? ?? json['message'] as String?,
    );
  }
}
