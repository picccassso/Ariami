/// Service for scanning directories and discovering audio files
class FileScanner {
  /// Supported audio file extensions
  static const supportedExtensions = [
    '.mp3', '.m4a', '.mp4', // Common formats
    '.flac', '.wav', '.aiff', // Lossless formats
    '.ogg', '.opus', '.wma', // Other formats
    '.aac', '.alac', // Apple formats
  ];
}
