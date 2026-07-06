import 'dart:convert';
import 'dart:typed_data';

/// Minimal DNS wire-format codec — just enough of mDNS (RFC 6762) and DNS-SD
/// (RFC 6763) to advertise and browse the Ariami service.
///
/// Decoding handles name compression pointers (queries and responses from
/// real resolvers use them); encoding always writes uncompressed names,
/// which is legal and keeps the writer trivial — these packets are tiny.
class DnsType {
  DnsType._();
  static const int a = 1;
  static const int ptr = 12;
  static const int txt = 16;
  static const int aaaa = 28;
  static const int srv = 33;
  static const int any = 255;
}

class DnsClass {
  DnsClass._();
  static const int internet = 1;

  /// Top bit of the class field: "unicast response requested" on questions,
  /// "cache flush" on records (RFC 6762 §5.4, §10.2).
  static const int topBit = 0x8000;
}

/// Case-insensitive DNS name comparison (names are ASCII labels).
bool dnsNamesEqual(String a, String b) => a.toLowerCase() == b.toLowerCase();

class DnsQuestion {
  const DnsQuestion({
    required this.name,
    required this.type,
    this.qclass = DnsClass.internet,
  });

  final String name;
  final int type;
  final int qclass;

  /// Whether the querier asked for a unicast response (QU bit).
  bool get unicastResponse => qclass & DnsClass.topBit != 0;
}

/// A resource record. Only the fields for the record's [type] are
/// meaningful: [target] for PTR and SRV, [port] for SRV, [address] for A,
/// [txt] for TXT.
class DnsRecord {
  const DnsRecord({
    required this.name,
    required this.type,
    required this.ttl,
    this.cacheFlush = false,
    this.target,
    this.port = 0,
    this.address,
    this.txt = const <String>[],
  });

  final String name;
  final int type;
  final int ttl;
  final bool cacheFlush;
  final String? target;
  final int port;
  final String? address;
  final List<String> txt;
}

class DnsMessage {
  const DnsMessage({
    this.id = 0,
    this.flags = 0,
    this.questions = const <DnsQuestion>[],
    this.records = const <DnsRecord>[],
  });

  final int id;
  final int flags;
  final List<DnsQuestion> questions;

  /// Answer, authority and additional records, flattened — mDNS consumers
  /// treat them uniformly.
  final List<DnsRecord> records;

  bool get isResponse => flags & 0x8000 != 0;

  /// QR + AA: the flags every mDNS response carries (RFC 6762 §18).
  static const int responseFlags = 0x8400;

  /// Parses a packet, returning null when it is not a well-formed DNS
  /// message (mDNS sockets receive plenty of unrelated traffic).
  static DnsMessage? parse(Uint8List bytes) {
    try {
      return _DnsReader(bytes).readMessage();
    } catch (_) {
      return null;
    }
  }

  /// Encodes a message. Records in [answers] land in the answer section,
  /// [additionals] in the additional section.
  static Uint8List encode({
    int id = 0,
    int flags = 0,
    List<DnsQuestion> questions = const <DnsQuestion>[],
    List<DnsRecord> answers = const <DnsRecord>[],
    List<DnsRecord> additionals = const <DnsRecord>[],
  }) {
    final out = BytesBuilder(copy: false);
    _writeU16(out, id);
    _writeU16(out, flags);
    _writeU16(out, questions.length);
    _writeU16(out, answers.length);
    _writeU16(out, 0);
    _writeU16(out, additionals.length);
    for (final question in questions) {
      _writeName(out, question.name);
      _writeU16(out, question.type);
      _writeU16(out, question.qclass);
    }
    for (final record in answers) {
      _writeRecord(out, record);
    }
    for (final record in additionals) {
      _writeRecord(out, record);
    }
    return out.toBytes();
  }

  static void _writeU16(BytesBuilder out, int value) {
    out.addByte((value >> 8) & 0xff);
    out.addByte(value & 0xff);
  }

  static void _writeU32(BytesBuilder out, int value) {
    out.addByte((value >> 24) & 0xff);
    out.addByte((value >> 16) & 0xff);
    out.addByte((value >> 8) & 0xff);
    out.addByte(value & 0xff);
  }

  static void _writeName(BytesBuilder out, String name) {
    for (final label in name.split('.')) {
      if (label.isEmpty) continue;
      final bytes = utf8.encode(label);
      if (bytes.length > 63) {
        throw const FormatException('DNS label longer than 63 bytes');
      }
      out.addByte(bytes.length);
      out.add(bytes);
    }
    out.addByte(0);
  }

  static void _writeRecord(BytesBuilder out, DnsRecord record) {
    _writeName(out, record.name);
    _writeU16(out, record.type);
    _writeU16(
      out,
      DnsClass.internet | (record.cacheFlush ? DnsClass.topBit : 0),
    );
    _writeU32(out, record.ttl);

    final rdata = BytesBuilder(copy: false);
    switch (record.type) {
      case DnsType.ptr:
        _writeName(rdata, record.target ?? '');
        break;
      case DnsType.srv:
        _writeU16(rdata, 0); // priority
        _writeU16(rdata, 0); // weight
        _writeU16(rdata, record.port);
        _writeName(rdata, record.target ?? '');
        break;
      case DnsType.txt:
        if (record.txt.isEmpty) {
          rdata.addByte(0);
        } else {
          for (final entry in record.txt) {
            final bytes = utf8.encode(entry);
            if (bytes.length > 255) {
              throw const FormatException('TXT entry longer than 255 bytes');
            }
            rdata.addByte(bytes.length);
            rdata.add(bytes);
          }
        }
        break;
      case DnsType.a:
        final parts = (record.address ?? '').split('.');
        if (parts.length != 4) {
          throw FormatException('Bad IPv4 address: ${record.address}');
        }
        for (final part in parts) {
          rdata.addByte(int.parse(part));
        }
        break;
      default:
        throw FormatException('Unsupported record type: ${record.type}');
    }

    final rdataBytes = rdata.toBytes();
    _writeU16(out, rdataBytes.length);
    out.add(rdataBytes);
  }
}

class _DnsReader {
  _DnsReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  DnsMessage readMessage() {
    final id = _readU16();
    final flags = _readU16();
    final questionCount = _readU16();
    final answerCount = _readU16();
    final authorityCount = _readU16();
    final additionalCount = _readU16();

    final questions = <DnsQuestion>[
      for (var i = 0; i < questionCount; i++) _readQuestion(),
    ];
    final recordCount = answerCount + authorityCount + additionalCount;
    final records = <DnsRecord>[];
    for (var i = 0; i < recordCount; i++) {
      final record = _readRecord();
      if (record != null) records.add(record);
    }
    return DnsMessage(
      id: id,
      flags: flags,
      questions: questions,
      records: records,
    );
  }

  DnsQuestion _readQuestion() {
    final name = _readName();
    final type = _readU16();
    final qclass = _readU16();
    return DnsQuestion(name: name, type: type, qclass: qclass);
  }

  DnsRecord? _readRecord() {
    final name = _readName();
    final type = _readU16();
    final rclass = _readU16();
    final ttl = _readU32();
    final rdataLength = _readU16();
    final rdataEnd = offset + rdataLength;
    if (rdataEnd > bytes.length) {
      throw const FormatException('Record data exceeds packet');
    }
    final cacheFlush = rclass & DnsClass.topBit != 0;

    DnsRecord? record;
    switch (type) {
      case DnsType.ptr:
        record = DnsRecord(
          name: name,
          type: type,
          ttl: ttl,
          cacheFlush: cacheFlush,
          target: _readName(),
        );
        break;
      case DnsType.srv:
        _readU16(); // priority
        _readU16(); // weight
        final port = _readU16();
        record = DnsRecord(
          name: name,
          type: type,
          ttl: ttl,
          cacheFlush: cacheFlush,
          port: port,
          target: _readName(),
        );
        break;
      case DnsType.txt:
        final txt = <String>[];
        while (offset < rdataEnd) {
          final length = bytes[offset];
          offset += 1;
          if (offset + length > rdataEnd) break;
          if (length > 0) {
            txt.add(utf8.decode(
              bytes.sublist(offset, offset + length),
              allowMalformed: true,
            ));
          }
          offset += length;
        }
        record = DnsRecord(
          name: name,
          type: type,
          ttl: ttl,
          cacheFlush: cacheFlush,
          txt: txt,
        );
        break;
      case DnsType.a:
        if (rdataLength == 4) {
          record = DnsRecord(
            name: name,
            type: type,
            ttl: ttl,
            cacheFlush: cacheFlush,
            address: bytes.sublist(offset, offset + 4).join('.'),
          );
        }
        break;
      default:
        // Unknown types (AAAA, NSEC, OPT, …) are skipped, not errors.
        break;
    }

    offset = rdataEnd;
    return record;
  }

  /// Reads a possibly-compressed name starting at [offset], leaving [offset]
  /// just past the name in the original byte stream.
  String _readName() {
    final labels = <String>[];
    var position = offset;
    var jumped = false;
    var jumps = 0;

    while (true) {
      if (position >= bytes.length) {
        throw const FormatException('Name runs past packet end');
      }
      final length = bytes[position];
      if (length == 0) {
        position += 1;
        break;
      }
      if (length & 0xc0 == 0xc0) {
        if (position + 1 >= bytes.length) {
          throw const FormatException('Truncated compression pointer');
        }
        final pointer = ((length & 0x3f) << 8) | bytes[position + 1];
        if (!jumped) offset = position + 2;
        jumped = true;
        if (++jumps > 32) {
          throw const FormatException('Compression pointer loop');
        }
        position = pointer;
        continue;
      }
      if (length & 0xc0 != 0) {
        throw const FormatException('Reserved label type');
      }
      if (position + 1 + length > bytes.length) {
        throw const FormatException('Label runs past packet end');
      }
      labels.add(utf8.decode(
        bytes.sublist(position + 1, position + 1 + length),
        allowMalformed: true,
      ));
      if (labels.length > 128) {
        throw const FormatException('Too many labels');
      }
      position += 1 + length;
    }

    if (!jumped) offset = position;
    return labels.join('.');
  }

  int _readU16() {
    if (offset + 2 > bytes.length) {
      throw const FormatException('Packet too short');
    }
    final value = (bytes[offset] << 8) | bytes[offset + 1];
    offset += 2;
    return value;
  }

  int _readU32() {
    if (offset + 4 > bytes.length) {
      throw const FormatException('Packet too short');
    }
    final value = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    offset += 4;
    return value;
  }
}
