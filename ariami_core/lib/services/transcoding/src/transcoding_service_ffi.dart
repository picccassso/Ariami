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

class _SonicFfiAdapter {
  static const int abiVersion = 1;
  static const int statusOk = 0;
  static const int statusNotImplemented = 5;
  static const int presetLow = 0;
  static const int presetMedium = 1;

  final String libraryPath;
  final ffi.DynamicLibrary _library;

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
  late final _SonicAbiVersionDart _abiVersion =
      _library.lookupFunction<_SonicAbiVersionNative, _SonicAbiVersionDart>(
    'sonic_ffi_abi_version',
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

  _SonicFfiAdapter._(this.libraryPath, this._library);

  static _SonicFfiAdapter? tryLoad(String candidatePath) {
    try {
      final library = ffi.DynamicLibrary.open(candidatePath);
      final adapter = _SonicFfiAdapter._(candidatePath, library);
      if (adapter._abiVersion() != abiVersion) {
        return null;
      }
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
    final fn = _transcodeFileToFile;
    if (fn == null) {
      return _SonicFfiTranscodeResult(
        status: statusNotImplemented,
        outputBytes: null,
      );
    }

    final inPathPtr = inputPath.toNativeUtf8().cast<ffi.Int8>();
    final outPathPtr = outputPath.toNativeUtf8().cast<ffi.Int8>();
    final outErrorPtrPtr = pkg_ffi.calloc<ffi.Pointer<ffi.Int8>>();

    try {
      final status = fn(
        inPathPtr,
        preset,
        outPathPtr,
        outErrorPtrPtr,
      );

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
    }
  }

  Future<_SonicFfiTranscodeResult> transcodeFileToFileAsync(
    String inputPath,
    String outputPath,
    int preset,
  ) async {
    final libPath = libraryPath;
    final result = await Isolate.run<List<Object?>>(() {
      final isolateAdapter = _SonicFfiAdapter.tryLoad(libPath);
      if (isolateAdapter == null) {
        return <Object?>[
          1,
          'Failed to load Sonic FFI library in isolate: $libPath',
        ];
      }

      final transcodeResult = isolateAdapter.transcodeFileToFile(
        inputPath,
        outputPath,
        preset,
      );

      return <Object?>[
        transcodeResult.status,
        transcodeResult.errorMessage,
      ];
    });

    return _SonicFfiTranscodeResult(
      status: (result.isNotEmpty ? result[0] : 1) as int,
      outputBytes: null,
      errorMessage: result.length > 1 ? result[1] as String? : null,
    );
  }
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
