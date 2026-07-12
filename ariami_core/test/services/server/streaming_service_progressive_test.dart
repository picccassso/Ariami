import 'dart:async';
import 'dart:io';

import 'package:ariami_core/services/server/streaming_service.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ariami_growing_stream_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('cold transcode returns response before the complete file exists',
      () async {
    final service = StreamingService();
    final partial = File('${tempDir.path}/track.aac.partial');
    final finalFile = File('${tempDir.path}/track.aac');
    final completion = Completer<File?>();
    var doneCalls = 0;

    final responseFuture = service.streamGrowingTranscode(
      partialFile: partial,
      completion: completion.future,
      request: Request('GET', Uri.parse('http://localhost/stream')),
      mimeType: 'audio/aac',
      onDone: () => doneCalls++,
    );

    await Future<void>.delayed(const Duration(milliseconds: 25));
    await partial.writeAsBytes(<int>[1, 2, 3], flush: true);
    final response = await responseFuture.timeout(const Duration(seconds: 1));

    expect(response, isNotNull);
    expect(response!.statusCode, 200);
    expect(response.headers[HttpHeaders.contentLengthHeader], isNull);
    expect(completion.isCompleted, isFalse);

    final bytesFuture = response.read().expand((chunk) => chunk).toList();
    await partial.writeAsBytes(
      <int>[4, 5, 6],
      mode: FileMode.append,
      flush: true,
    );
    await partial.rename(finalFile.path);
    completion.complete(finalFile);

    expect(await bytesFuture, <int>[1, 2, 3, 4, 5, 6]);
    expect(doneCalls, 1);
  });

  test('non-initial range waits for stable completed file semantics', () async {
    final service = StreamingService();
    final partial = File('${tempDir.path}/seek.aac.partial');
    final finalFile = File('${tempDir.path}/seek.aac');
    final completion = Completer<File?>();

    final responseFuture = service.streamGrowingTranscode(
      partialFile: partial,
      completion: completion.future,
      request: Request(
        'GET',
        Uri.parse('http://localhost/stream'),
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=2-4'},
      ),
      mimeType: 'audio/aac',
    );

    await partial.writeAsBytes(<int>[1, 2, 3], flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(completion.isCompleted, isFalse);

    await partial.writeAsBytes(
      <int>[4, 5, 6],
      mode: FileMode.append,
      flush: true,
    );
    await partial.rename(finalFile.path);
    completion.complete(finalFile);

    final response = await responseFuture;
    expect(response, isNotNull);
    expect(response!.statusCode, 206);
    expect(await response.read().expand((chunk) => chunk).toList(),
        <int>[3, 4, 5]);
  });
}
