import 'dart:io';

import 'package:shelf/shelf.dart';

/// Compress JSON API responses when the client advertises gzip support.
///
/// Catalog payloads are highly repetitive and commonly shrink by an order of
/// magnitude, which materially reduces bootstrap time over cellular/DERP paths.
Middleware gzipJsonResponses() {
  return (Handler inner) {
    return (Request request) async {
      final acceptsGzip = request.headers[HttpHeaders.acceptEncodingHeader]
              ?.split(',')
              .map((value) => value.trim().split(';').first.toLowerCase())
              .contains('gzip') ??
          false;
      if (!acceptsGzip || request.method == 'HEAD') return inner(request);

      final response = await inner(request);
      final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
      if (!contentType.toLowerCase().startsWith('application/json') ||
          response.headers.containsKey(HttpHeaders.contentEncodingHeader) ||
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.notModified) {
        return response;
      }

      final bodyBytes = await response.read().expand((chunk) => chunk).toList();
      final compressed = gzip.encode(bodyBytes);
      final existingVary = response.headers[HttpHeaders.varyHeader];
      final vary = existingVary == null || existingVary.isEmpty
          ? HttpHeaders.acceptEncodingHeader
          : '$existingVary, ${HttpHeaders.acceptEncodingHeader}';
      return response.change(
        body: compressed,
        headers: <String, String>{
          HttpHeaders.contentEncodingHeader: 'gzip',
          HttpHeaders.contentLengthHeader: '${compressed.length}',
          HttpHeaders.varyHeader: vary,
        },
      );
    };
  };
}
