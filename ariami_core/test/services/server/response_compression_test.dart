import 'dart:convert';
import 'dart:io';

import 'package:ariami_core/services/server/response_compression.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test('gzip-compresses JSON when requested and preserves its representation',
      () async {
    final payload = jsonEncode(<String, Object>{
      'songs': List<String>.filled(200, 'repeated catalog metadata'),
    });
    final handler = gzipJsonResponses()((_) async => Response.ok(
          payload,
          headers: <String, String>{
            HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          },
        ));

    final response = await handler(Request(
      'GET',
      Uri.parse('http://localhost/api/v2/bootstrap'),
      headers: <String, String>{HttpHeaders.acceptEncodingHeader: 'gzip'},
    ));
    final compressed = await response.read().expand((chunk) => chunk).toList();

    expect(response.headers[HttpHeaders.contentEncodingHeader], 'gzip');
    expect(
        response.headers[HttpHeaders.varyHeader], contains('accept-encoding'));
    expect(compressed.length, lessThan(utf8.encode(payload).length));
    expect(utf8.decode(gzip.decode(compressed)), payload);
  });

  test('leaves media and clients without gzip support untouched', () async {
    final handler = gzipJsonResponses()((request) async => Response.ok(
          <int>[1, 2, 3],
          headers: <String, String>{
            HttpHeaders.contentTypeHeader: 'audio/aac',
          },
        ));

    final response = await handler(
      Request('GET', Uri.parse('http://localhost/api/stream/song')),
    );
    expect(response.headers[HttpHeaders.contentEncodingHeader], isNull);
    expect(await response.read().expand((chunk) => chunk).toList(),
        <int>[1, 2, 3]);
  });
}
