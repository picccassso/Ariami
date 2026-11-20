import 'dart:io';

import 'package:shelf/shelf.dart';

/// Compress JSON API responses when the client advertises gzip support.
///
/// Catalog payloads are highly repetitive and commonly shrink by an order of
/// magnitude, which materially reduces bootstrap time over cellular/DERP paths.
Middleware gzipJsonResponses() {
  return (Handler inner) {
    return (Request request) async {
      if (!_acceptsGzip(request) || request.method == 'HEAD') {
        return inner(request);
      }

      final response = await inner(request);
      final contentType = response.headers[HttpHeaders.contentTypeHeader] ?? '';
      if (!contentType.toLowerCase().startsWith('application/json') ||
          response.headers.containsKey(HttpHeaders.contentEncodingHeader) ||
          response.statusCode == HttpStatus.noContent ||
          response.statusCode == HttpStatus.notModified) {
        return response;
      }

      return _withGzipBody(response, gzip.encode(await _readBody(response)));
    };
  };
}

final _compressibleStatic = RegExp(r'javascript|json|wasm|font|^text/');

/// Gzips compressible static files (the web player bundle). Each file is
/// compressed once and reused until its Last-Modified changes.
Handler gzipStaticFiles(Handler inner) {
  final cache = <String, (String, List<int>)>{};
  return (Request request) async {
    final response = await inner(request);
    if (request.method != 'GET' ||
        response.statusCode != HttpStatus.ok ||
        !_acceptsGzip(request) ||
        response.headers.containsKey(HttpHeaders.contentEncodingHeader) ||
        !_compressibleStatic
            .hasMatch(response.headers[HttpHeaders.contentTypeHeader] ?? '')) {
      return response;
    }
    final version = response.headers[HttpHeaders.lastModifiedHeader] ?? '';
    var entry = cache[request.url.path];
    if (entry == null || entry.$1 != version) {
      entry = (version, gzip.encode(await _readBody(response)));
      cache[request.url.path] = entry;
    }
    return _withGzipBody(response, entry.$2);
  };
}

bool _acceptsGzip(Request request) =>
    request.headers[HttpHeaders.acceptEncodingHeader]
        ?.split(',')
        .map((value) => value.trim().split(';').first.toLowerCase())
        .contains('gzip') ??
    false;

Future<List<int>> _readBody(Response response) =>
    response.read().expand((chunk) => chunk).toList();

Response _withGzipBody(Response response, List<int> compressed) {
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
}
