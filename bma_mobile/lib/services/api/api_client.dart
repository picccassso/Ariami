import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/server_info.dart';
import '../../models/connection_response.dart';

class ApiClient {
  final ServerInfo serverInfo;
  final Duration timeout;

  ApiClient({
    required this.serverInfo,
    this.timeout = const Duration(seconds: 30),
  });

  String get _baseUrl => serverInfo.baseUrl;

  // Connection methods
  Future<bool> ping() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/ping'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      print('Ping failed: $e');
      return false;
    }
  }

  Future<ConnectionResponse?> connect({
    required String deviceId,
    required String deviceName,
    required String appVersion,
    required String platform,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/connect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': deviceName,
              'appVersion': appVersion,
              'platform': platform,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ConnectionResponse.fromJson(data);
      } else {
        print('Connect failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Connect error: $e');
      return null;
    }
  }

  Future<bool> disconnect(String sessionId) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/disconnect'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'sessionId': sessionId}),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == 'disconnected';
      }
      return false;
    } catch (e) {
      print('Disconnect error: $e');
      return false;
    }
  }

  // Library methods
  Future<LibraryResponse?> getLibrary() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/library'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return LibraryResponse.fromJson(data);
      } else {
        print('Get library failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Get library error: $e');
      return null;
    }
  }

  Future<AlbumInfo?> getAlbum(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/albums/$id'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AlbumInfo.fromJson(data);
      } else {
        print('Get album failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Get album error: $e');
      return null;
    }
  }

  Future<SongInfo?> getSong(String id) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/songs/$id'))
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return SongInfo.fromJson(data);
      } else {
        print('Get song failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Get song error: $e');
      return null;
    }
  }

  // Streaming URLs (to be used with audio player)
  String getStreamUrl(String songId) {
    return '$_baseUrl/api/stream/$songId';
  }

  String getArtworkUrl(String albumId) {
    return '$_baseUrl/api/artwork/$albumId';
  }
}
