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
