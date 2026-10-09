import 'package:crypto/crypto.dart';
import 'dart:convert';

/// Generates a stable album ID from display title and artist.
///
/// Must stay in sync with [AlbumBuilder] final album identity rules.
String generateAlbumId(String title, String artist) {
  final input = '$title|||$artist'.toLowerCase();
  final bytes = utf8.encode(input);
  final digest = md5.convert(bytes);
  return digest.toString();
}

/// Generates a stable song ID (first 12 hex chars of the MD5) from a file
/// path.
String generateSongId(String filePath) {
  return md5.convert(utf8.encode(filePath)).toString().substring(0, 12);
}
