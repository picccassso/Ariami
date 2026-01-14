import 'dart:io';
import 'dart:typed_data';

/// Pure Dart MP3 duration parser
/// 
/// Parses MP3 file headers to calculate duration without external dependencies.
/// Supports both CBR (Constant Bit Rate) and VBR (Variable Bit Rate) files.
class Mp3DurationParser {
  // MPEG Audio version ID
  static const int _mpegVersionReserved = 1;
  static const int _mpegVersion1 = 3; // MPEG 1

  // Layer description
  static const int _layerReserved = 0;
  static const int _layer1 = 3; // Layer I

  // Bitrate lookup tables (in kbps)
  // Index by [version][layer][bitrate_index]
  // Version: 0 = MPEG 2/2.5, 1 = MPEG 1
  // Layer: 0 = Layer I, 1 = Layer II, 2 = Layer III
  static const List<List<List<int>>> _bitrates = [
    // MPEG 2 & 2.5
    [
      [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, 0], // Layer I
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], // Layer II
      [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0], // Layer III
    ],
    // MPEG 1
    [
      [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0], // Layer I
      [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0], // Layer II
      [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0], // Layer III
    ],
  ];

  // Sample rate lookup tables (in Hz)
  // Index by [version][samplerate_index]
  static const List<List<int>> _sampleRates = [
    [11025, 12000, 8000, 0], // MPEG 2.5
    [0, 0, 0, 0], // Reserved
    [22050, 24000, 16000, 0], // MPEG 2
    [44100, 48000, 32000, 0], // MPEG 1
  ];

  // Samples per frame
  // Index by [version][layer]
  static const List<List<int>> _samplesPerFrame = [
    [384, 1152, 576], // MPEG 2.5: Layer I, II, III
    [0, 0, 0], // Reserved
    [384, 1152, 576], // MPEG 2: Layer I, II, III
    [384, 1152, 1152], // MPEG 1: Layer I, II, III
  ];

  /// Parse an MP3 file and return its duration in seconds
  ///
  /// Returns null if the file cannot be parsed or is not a valid MP3.
  /// Uses a single file open/close cycle for efficiency.
  Future<int?> getDuration(String filePath) async {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final fileSize = await file.length();
      if (fileSize < 10) return null;

      // Open file once for all reads
      raf = await file.open(mode: FileMode.read);

      // Step 1: Read ID3v2 header (10 bytes) to determine tag size
      final headerBytes = await raf.read(10);
      final audioDataOffset = _skipId3v2Header(headerBytes);

      // Step 2: Calculate audio data size and validate
      final audioDataSize = fileSize - audioDataOffset;
      if (audioDataSize < 10) return null; // No audio data

      // Step 3: Seek to audio data and read (up to 64KB)
      await raf.setPosition(audioDataOffset);
      final readSize = audioDataSize < 65536 ? audioDataSize : 65536;
      final bytes = await raf.read(readSize.toInt());

      // Step 4: Find first valid frame header (searching from offset 0 in audio buffer)
      final frameHeader = _findFirstFrameHeader(bytes, 0);
      if (frameHeader == null) return null;

      // Try to find XING/VBRI header for VBR files
      final vbrInfo = _parseVbrHeader(bytes, frameHeader);

      if (vbrInfo != null && vbrInfo.totalFrames > 0) {
        // VBR: Calculate from total frames
        final samplesPerFrame = _getSamplesPerFrame(frameHeader.version, frameHeader.layer);
        final totalSamples = vbrInfo.totalFrames * samplesPerFrame;
        final durationSeconds = totalSamples / frameHeader.sampleRate;
        return durationSeconds.round(); // Return seconds
      }

      // CBR: Calculate from audio data size and bitrate
      // Account for ID3v1 tag at end (128 bytes)
      final audioBytesForCalc = audioDataSize - 128; // Subtract possible ID3v1 tag
      if (frameHeader.bitrate > 0 && audioBytesForCalc > 0) {
        final durationSeconds = (audioBytesForCalc * 8) / (frameHeader.bitrate * 1000);
        return durationSeconds.round(); // Return seconds
      }

      return null;
    } catch (e) {
      // Silently fail - duration is optional
      return null;
    } finally {
      // Always close file handle
      await raf?.close();
    }
  }

  /// Skip ID3v2 header and return offset to audio data
  int _skipId3v2Header(Uint8List bytes) {
    if (bytes.length < 10) return 0;

    // Check for ID3v2 header: "ID3"
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      // ID3v2 size is stored as syncsafe integer (7 bits per byte)
      final size = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);
      return 10 + size; // Header (10 bytes) + tag data
    }

    return 0;
  }

  /// Find the first valid MP3 frame header
  _Mp3FrameHeader? _findFirstFrameHeader(Uint8List bytes, int startOffset) {
    // Search for sync word (0xFF followed by 0xE0 or higher)
    for (var i = startOffset; i < bytes.length - 4; i++) {
      if (bytes[i] == 0xFF && (bytes[i + 1] & 0xE0) == 0xE0) {
        final header = _parseFrameHeader(bytes, i);
        if (header != null) {
          return header;
        }
      }
    }
    return null;
  }

  /// Parse a frame header at the given offset
  _Mp3FrameHeader? _parseFrameHeader(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return null;

    final b1 = bytes[offset];
    final b2 = bytes[offset + 1];
    final b3 = bytes[offset + 2];

    // Verify sync word
    if (b1 != 0xFF || (b2 & 0xE0) != 0xE0) return null;

    // Extract header fields
    final version = (b2 >> 3) & 0x03;
    final layer = (b2 >> 1) & 0x03;
    final bitrateIndex = (b3 >> 4) & 0x0F;
    final sampleRateIndex = (b3 >> 2) & 0x03;
    final padding = (b3 >> 1) & 0x01;

    // Validate
    if (version == _mpegVersionReserved) return null;
    if (layer == _layerReserved) return null;
    if (bitrateIndex == 0 || bitrateIndex == 15) return null;
    if (sampleRateIndex == 3) return null;

    // Look up values
    final versionIndex = (version == _mpegVersion1) ? 1 : 0;
    final layerIndex = 3 - layer; // Convert to 0=I, 1=II, 2=III

    final bitrate = _bitrates[versionIndex][layerIndex][bitrateIndex];
    final sampleRate = _sampleRates[version][sampleRateIndex];

    if (bitrate == 0 || sampleRate == 0) return null;

    // Calculate frame size
    int frameSize;
    if (layer == _layer1) {
      frameSize = ((12 * bitrate * 1000) ~/ sampleRate + padding) * 4;
    } else {
      final coefficient = (version == _mpegVersion1) ? 144 : 72;
      frameSize = (coefficient * bitrate * 1000) ~/ sampleRate + padding;
    }

    return _Mp3FrameHeader(
      offset: offset,
      version: version,
      layer: layer,
      bitrate: bitrate,
      sampleRate: sampleRate,
      frameSize: frameSize,
      padding: padding == 1,
    );
  }

  /// Get samples per frame for the given version and layer
  int _getSamplesPerFrame(int version, int layer) {
    final layerIndex = 3 - layer; // Convert to 0=I, 1=II, 2=III
    return _samplesPerFrame[version][layerIndex];
  }

  /// Parse XING or VBRI header for VBR info
  _VbrInfo? _parseVbrHeader(Uint8List bytes, _Mp3FrameHeader frameHeader) {
    // XING/Info header is located after the frame header
    // Position depends on MPEG version and channel mode
    final headerOffset = frameHeader.offset + 4; // Skip frame header
    
    // Side info size varies by version
    // MPEG1: 32 bytes (stereo) or 17 bytes (mono)
    // MPEG2/2.5: 17 bytes (stereo) or 9 bytes (mono)
    // We'll check both common positions
    final possibleOffsets = [
      headerOffset + 32, // MPEG1 stereo
      headerOffset + 17, // MPEG1 mono / MPEG2 stereo
      headerOffset + 9,  // MPEG2 mono
    ];

    for (final offset in possibleOffsets) {
      if (offset + 12 > bytes.length) continue;

      // Check for "Xing" or "Info" header
      if (_matchesTag(bytes, offset, 'Xing') || _matchesTag(bytes, offset, 'Info')) {
        return _parseXingHeader(bytes, offset);
      }
    }

    // Check for VBRI header (always at fixed position: 32 bytes after frame header)
    final vbriOffset = headerOffset + 32;
    if (vbriOffset + 26 <= bytes.length && _matchesTag(bytes, vbriOffset, 'VBRI')) {
      return _parseVbriHeader(bytes, vbriOffset);
    }

    return null;
  }

  /// Check if bytes at offset match a tag string
  bool _matchesTag(Uint8List bytes, int offset, String tag) {
    if (offset + tag.length > bytes.length) return false;
    for (var i = 0; i < tag.length; i++) {
      if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// Parse XING header
  _VbrInfo? _parseXingHeader(Uint8List bytes, int offset) {
    if (offset + 8 > bytes.length) return null;

    final flags = (bytes[offset + 4] << 24) |
        (bytes[offset + 5] << 16) |
        (bytes[offset + 6] << 8) |
        bytes[offset + 7];

    var pos = offset + 8;
    int? totalFrames;
    int? totalBytes;

    // Frames flag (bit 0)
    if ((flags & 0x01) != 0) {
      if (pos + 4 > bytes.length) return null;
      totalFrames = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      pos += 4;
    }

    // Bytes flag (bit 1)
    if ((flags & 0x02) != 0) {
      if (pos + 4 > bytes.length) return null;
      totalBytes = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      pos += 4;
    }

    return _VbrInfo(totalFrames: totalFrames ?? 0, totalBytes: totalBytes);
  }

  /// Parse VBRI header (Fraunhofer encoder)
  _VbrInfo? _parseVbriHeader(Uint8List bytes, int offset) {
    if (offset + 26 > bytes.length) return null;

    // Total bytes at offset + 10 (4 bytes, big-endian)
    final totalBytes = (bytes[offset + 10] << 24) |
        (bytes[offset + 11] << 16) |
        (bytes[offset + 12] << 8) |
        bytes[offset + 13];

    // Total frames at offset + 14 (4 bytes, big-endian)
    final totalFrames = (bytes[offset + 14] << 24) |
        (bytes[offset + 15] << 16) |
        (bytes[offset + 16] << 8) |
        bytes[offset + 17];

    return _VbrInfo(totalFrames: totalFrames, totalBytes: totalBytes);
  }
}

/// Parsed MP3 frame header data
class _Mp3FrameHeader {
  final int offset;
  final int version;
  final int layer;
  final int bitrate; // in kbps
  final int sampleRate; // in Hz
  final int frameSize;
  final bool padding;

  _Mp3FrameHeader({
    required this.offset,
    required this.version,
    required this.layer,
    required this.bitrate,
    required this.sampleRate,
    required this.frameSize,
    required this.padding,
  });
}

/// VBR (Variable Bit Rate) info from XING or VBRI header
class _VbrInfo {
  final int totalFrames;
  final int? totalBytes;

  _VbrInfo({required this.totalFrames, this.totalBytes});
}

