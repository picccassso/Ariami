import 'package:path/path.dart' as path;

/// Attempts to infer track number from filename prefixes like:
/// "01 - Title", "1. Title", "07_Title", "12 Title".
int? inferTrackNumberFromFilename(String filePath) {
  final fileName = path.basenameWithoutExtension(filePath).trim();
  final match = RegExp(r'^(\d{1,3})(?:\s*[-._)]\s*|\s+)').firstMatch(fileName);
  if (match == null) return null;

  final parsed = int.tryParse(match.group(1)!);
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}
