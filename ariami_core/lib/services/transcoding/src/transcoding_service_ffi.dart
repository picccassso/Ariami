part of 'package:ariami_core/services/transcoding/transcoding_service.dart';

typedef _SonicTranscodeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  ffi.IntPtr inputLen,
  ffi.Uint32 preset,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>> outDataPtr,
  ffi.Pointer<ffi.IntPtr> outDataLen,
  ffi.Pointer<ffi.IntPtr> outDataCap,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

typedef _SonicTranscodeDart = int Function(
  ffi.Pointer<ffi.Uint8> inputPtr,
  int inputLen,
  int preset,
  ffi.Pointer<ffi.Pointer<ffi.Uint8>> outDataPtr,
  ffi.Pointer<ffi.IntPtr> outDataLen,
  ffi.Pointer<ffi.IntPtr> outDataCap,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

typedef _SonicFreeBufferNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> ptr,
  ffi.IntPtr len,
  ffi.IntPtr cap,
);

typedef _SonicFreeBufferDart = void Function(
  ffi.Pointer<ffi.Uint8> ptr,
  int len,
  int cap,
);

typedef _SonicFreeCStringNative = ffi.Void Function(ffi.Pointer<ffi.Int8> ptr);
typedef _SonicFreeCStringDart = void Function(ffi.Pointer<ffi.Int8> ptr);

typedef _SonicAbiVersionNative = ffi.Uint32 Function();
typedef _SonicAbiVersionDart = int Function();

final class _SonicTranscodeOptions extends ffi.Struct {
  @ffi.Uint32()
  external int outputFormat;

  @ffi.Uint32()
  external int preset;

  @ffi.Uint32()
  external int bitrateKbps;

  @ffi.Uint32()
  external int reserved;
}

typedef _SonicTranscodeFileToFileNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8> inputPath,
  ffi.Uint32 preset,
  ffi.Pointer<ffi.Int8> outputPath,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

typedef _SonicTranscodeFileToFileDart = int Function(
  ffi.Pointer<ffi.Int8> inputPath,
  int preset,
  ffi.Pointer<ffi.Int8> outputPath,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

typedef _SonicTranscodeFileOptionsNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Int8> inputPath,
  ffi.Pointer<_SonicTranscodeOptions> options,
  ffi.Pointer<ffi.Int8> outputPath,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

typedef _SonicTranscodeFileOptionsDart = int Function(
  ffi.Pointer<ffi.Int8> inputPath,
  ffi.Pointer<_SonicTranscodeOptions> options,
  ffi.Pointer<ffi.Int8> outputPath,
  ffi.Pointer<ffi.Pointer<ffi.Int8>> outError,
);

class _SonicFfiAdapter {
  static const int legacyAbiVersion = 1;
  static const int optionsAbiVersion = 4;
  static const int statusOk = 0;
  static const int statusNotImplemented = 5;
  static const int presetLow = 0;
  static const int presetMedium = 1;
  static const int outputAac = 0;

  final String libraryPath;
  final ffi.DynamicLibrary _library;
  final int abiVersion;

  late final _SonicTranscodeDart _transcode =
      _library.lookupFunction<_SonicTranscodeNative, _SonicTranscodeDart>(
    'sonic_transcode_mp3_to_aac',
  );
  late final _SonicFreeBufferDart _freeBuffer =
      _library.lookupFunction<_SonicFreeBufferNative, _SonicFreeBufferDart>(
    'sonic_free_buffer',
  );
  late final _SonicFreeCStringDart _freeCString =
      _library.lookupFunction<_SonicFreeCStringNative, _SonicFreeCStringDart>(
    'sonic_free_c_string',
  );
  late final _SonicTranscodeFileToFileDart? _transcodeFileToFile = (() {
    try {
      return _library.lookupFunction<_SonicTranscodeFileToFileNative,
          _SonicTranscodeFileToFileDart>(
        'sonic_transcode_mp3_file_to_aac_file',
      );
    } catch (_) {
      return null;
    }
  })();
  late final _SonicTranscodeFileOptionsDart? _transcodeFileOptions = (() {
    try {
      return _library.lookupFunction<_SonicTranscodeFileOptionsNative,
          _SonicTranscodeFileOptionsDart>(
        'sonic_transcode_file',
      );
    } catch (_) {
      return null;
    }
  })();

  _SonicFfiAdapter._(this.libraryPath, this._library, this.abiVersion);

  static _SonicFfiAdapter? tryLoad(String candidatePath) {
    try {
      final library = ffi.DynamicLibrary.open(candidatePath);
      final abiVersion =
          library.lookupFunction<_SonicAbiVersionNative, _SonicAbiVersionDart>(
        'sonic_ffi_abi_version',
      )();
      if (abiVersion != legacyAbiVersion && abiVersion != optionsAbiVersion) {
        return null;
      }
      final adapter = _SonicFfiAdapter._(candidatePath, library, abiVersion);
      return adapter;
    } catch (_) {
      return null;
    }
  }

  int presetForQuality(QualityPreset quality) {
    switch (quality) {
      case QualityPreset.low:
        return presetLow;
      case QualityPreset.medium:
        return presetMedium;
      case QualityPreset.high:
        throw ArgumentError('Sonic preset is not defined for high quality');
    }
  }

  _SonicFfiTranscodeResult transcode(Uint8List inputBytes, int preset) {
    final inPtr = pkg_ffi.calloc<ffi.Uint8>(inputBytes.length);
    final outDataPtrPtr = pkg_ffi.calloc<ffi.Pointer<ffi.Uint8>>();
    final outLenPtr = pkg_ffi.calloc<ffi.IntPtr>();
    final outCapPtr = pkg_ffi.calloc<ffi.IntPtr>();
    final outErrorPtrPtr = pkg_ffi.calloc<ffi.Pointer<ffi.Int8>>();

    try {
      inPtr.asTypedList(inputBytes.length).setAll(0, inputBytes);

      final status = _transcode(
        inPtr,
        inputBytes.length,
        preset,
        outDataPtrPtr,
        outLenPtr,
        outCapPtr,
        outErrorPtrPtr,
      );

      final outDataPtr = outDataPtrPtr.value;
      final outErrorPtr = outErrorPtrPtr.value;

      if (status == statusOk &&
          outDataPtr != ffi.nullptr &&
          outLenPtr.value > 0 &&
          outCapPtr.value >= outLenPtr.value) {
        try {
          final outputBytes =
              Uint8List.fromList(outDataPtr.asTypedList(outLenPtr.value));
          return _SonicFfiTranscodeResult(
            status: status,
            outputBytes: outputBytes,
          );
        } finally {
          _freeBuffer(outDataPtr, outLenPtr.value, outCapPtr.value);
        }
      }

      String? errorMessage;
      if (outErrorPtr != ffi.nullptr) {
        try {
          errorMessage = _readCString(outErrorPtr);
        } finally {
          _freeCString(outErrorPtr);
        }
      }

      return _SonicFfiTranscodeResult(
        status: status,
        outputBytes: null,
        errorMessage: errorMessage,
      );
    } finally {
      pkg_ffi.calloc.free(inPtr);
      pkg_ffi.calloc.free(outDataPtrPtr);
      pkg_ffi.calloc.free(outLenPtr);
      pkg_ffi.calloc.free(outCapPtr);
      pkg_ffi.calloc.free(outErrorPtrPtr);
    }
  }

  _SonicFfiTranscodeResult transcodeFileToFile(
    String inputPath,
    String outputPath,
    int preset,
  ) {
    final inPathPtr = inputPath.toNativeUtf8().cast<ffi.Int8>();
    final outPathPtr = outputPath.toNativeUtf8().cast<ffi.Int8>();
    final outErrorPtrPtr = pkg_ffi.calloc<ffi.Pointer<ffi.Int8>>();
    final optionsPtr = pkg_ffi.calloc<_SonicTranscodeOptions>();

    try {
      final optionsFn = _transcodeFileOptions;
      final legacyFn = _transcodeFileToFile;

      int status;
      if (optionsFn != null && abiVersion >= optionsAbiVersion) {
        optionsPtr.ref
          ..outputFormat = outputAac
          ..preset = preset
          ..bitrateKbps = 0
          ..reserved = 0;
        status = optionsFn(
          inPathPtr,
          optionsPtr,
          outPathPtr,
          outErrorPtrPtr,
        );
      } else if (legacyFn != null) {
        status = legacyFn(
          inPathPtr,
          preset,
          outPathPtr,
          outErrorPtrPtr,
        );
      } else {
        return _SonicFfiTranscodeResult(
          status: statusNotImplemented,
          outputBytes: null,
        );
      }

      final outErrorPtr = outErrorPtrPtr.value;
      String? errorMessage;
      if (outErrorPtr != ffi.nullptr) {
        try {
          errorMessage = _readCString(outErrorPtr);
        } finally {
          _freeCString(outErrorPtr);
        }
      }

      return _SonicFfiTranscodeResult(
        status: status,
        outputBytes: null,
        errorMessage: errorMessage,
      );
    } finally {
      pkg_ffi.calloc.free(inPathPtr);
      pkg_ffi.calloc.free(outPathPtr);
      pkg_ffi.calloc.free(outErrorPtrPtr);
      pkg_ffi.calloc.free(optionsPtr);
    }
  }

  Future<_SonicFfiTranscodeResult> transcodeFileToFileAsync(
    String inputPath,
    String outputPath,
    int preset, {
    Duration? timeout,
  }) async {
    final libPath = libraryPath;
    final receivePort = ReceivePort();
    Isolate? isolate;

    try {
      isolate = await Isolate.spawn<List<Object?>>(
        _sonicTranscodeFileIsolateMain,
        <Object?>[
          receivePort.sendPort,
          libPath,
          inputPath,
          outputPath,
          preset,
        ],
        errorsAreFatal: true,
      );

      final result = await (timeout == null
          ? receivePort.first
          : receivePort.first.timeout(timeout));
      final values = result as List<Object?>;
      return _SonicFfiTranscodeResult(
        status: (values.isNotEmpty ? values[0] : 1) as int,
        outputBytes: null,
        errorMessage: values.length > 1 ? values[1] as String? : null,
      );
    } on TimeoutException {
      isolate?.kill(priority: Isolate.immediate);
      return _SonicFfiTranscodeResult(
        status: 1,
        outputBytes: null,
        errorMessage: 'Sonic transcode timed out after $timeout',
      );
    } finally {
      receivePort.close();
    }
  }
}

void _sonicTranscodeFileIsolateMain(List<Object?> message) {
  final sendPort = message[0] as SendPort;
  final libPath = message[1] as String;
  final inputPath = message[2] as String;
  final outputPath = message[3] as String;
  final preset = message[4] as int;

  final isolateAdapter = _SonicFfiAdapter.tryLoad(libPath);
  if (isolateAdapter == null) {
    sendPort.send(<Object?>[
      1,
      'Failed to load Sonic FFI library in isolate: $libPath',
    ]);
    return;
  }

  final transcodeResult = isolateAdapter.transcodeFileToFile(
    inputPath,
    outputPath,
    preset,
  );
  sendPort.send(<Object?>[
    transcodeResult.status,
    transcodeResult.errorMessage,
  ]);
}

class _SonicFfiTranscodeResult {
  final int status;
  final Uint8List? outputBytes;
  final String? errorMessage;

  _SonicFfiTranscodeResult({
    required this.status,
    required this.outputBytes,
    this.errorMessage,
  });
}

String _readCString(ffi.Pointer<ffi.Int8> ptr) {
  final bytes = <int>[];
  var offset = 0;
  while (true) {
    final value = (ptr + offset).value;
    if (value == 0) break;
    bytes.add(value & 0xFF);
    offset++;
  }
  return utf8.decode(bytes, allowMalformed: true);
}
