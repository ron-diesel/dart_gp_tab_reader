import 'dart:typed_data';

import 'gpif_reader.dart';
import 'models.dart';

/// Reader for the Guitar Pro 6 `.gpx` container.
///
/// A `.gpx` file is a tiny proprietary filesystem ("BCFS") that is usually
/// wrapped in a bit-level LZ-style compression layer ("BCFZ"). Inside sits
/// the same `score.gpif` XML score that GP7/8 `.gp` zips carry, so once the
/// container is unpacked the score is handed to [parseGpif]. The container
/// logic is ported from alphaTab's `GpxFileSystem`/`BitReader` (MPL-2.0),
/// which documents the format.

/// Whether [bytes] start with the GP6 container magic (`BCFS` plain
/// filesystem or `BCFZ` compressed filesystem).
bool looksLikeGpx(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x42 && // B
    bytes[1] == 0x43 && // C
    bytes[2] == 0x46 && // F
    (bytes[3] == 0x53 || bytes[3] == 0x5A); // S | Z

/// Parses a Guitar Pro 6 `.gpx` file from its raw [bytes] into a [Song].
Song parseGpx(Uint8List bytes) {
  if (!looksLikeGpx(bytes)) {
    throw const GpException('not a .gpx file (missing BCFS/BCFZ header)');
  }
  final Uint8List filesystem;
  if (bytes[3] == 0x5A) {
    // BCFZ: decompress; the payload itself starts with a BCFS header, which
    // decompressBcfz strips together with everything before it.
    filesystem = decompressBcfz(bytes);
  } else {
    filesystem = Uint8List.sublistView(bytes, 4);
  }
  final score = bcfsFiles(filesystem)['score.gpif'];
  if (score == null) {
    throw const GpException('.gpx container has no score.gpif');
  }
  return parseGpif(score);
}

/// Decompresses a `BCFZ` [bytes] payload (including its 4-byte header) and
/// returns the contained filesystem with the inner `BCFS` header stripped.
///
/// The stream is a bit-level LZ variant: after a 32-bit expected length, each
/// chunk starts with one flag bit — `0` is a raw chunk (2-bit length, then
/// that many bytes), `1` is a back-reference (4-bit word size, then offset
/// and length of `wordSize` bits each, copied from already-decompressed
/// data). Bits are most-significant-first; offset/length fields are stored
/// least-significant-bit-first.
Uint8List decompressBcfz(Uint8List bytes) {
  final reader = _BitReader(bytes);
  reader.skipBytes(4); // BCFZ header
  final expectedLength = reader.readInt32();
  // Back-references read from anywhere in the already-decompressed data, so
  // decompress into one flat buffer that grows geometrically.
  var flat = Uint8List(expectedLength > 0 ? expectedLength + 4 : 1024);
  var length = 0;

  void append(List<int> data) {
    if (length + data.length > flat.length) {
      final grown = Uint8List((length + data.length) * 2 + 1024);
      grown.setRange(0, length, flat);
      flat = grown;
    }
    flat.setRange(length, length + data.length, data);
    length += data.length;
  }

  try {
    while (length < expectedLength) {
      if (reader.readBit() == 1) {
        // Back-reference: copy `min(offset, size)` bytes starting `offset`
        // bytes before the current end of the output.
        final wordSize = reader.readBits(4);
        final offset = reader.readBitsReversed(wordSize);
        final size = reader.readBitsReversed(wordSize);
        final sourcePosition = length - offset;
        final toRead = offset < size ? offset : size;
        if (sourcePosition < 0 || toRead < 0) {
          throw const GpException('corrupt BCFZ back-reference');
        }
        append(
          Uint8List.sublistView(flat, sourcePosition, sourcePosition + toRead),
        );
      } else {
        final size = reader.readBitsReversed(2);
        append([for (var i = 0; i < size; i++) reader.readByte()]);
      }
    }
  } on _EndOfStream {
    // Like the reference implementation, tolerate a truncated final chunk.
  }
  // Strip the inner "BCFS" header from the decompressed filesystem.
  const headerSize = 4;
  if (length < headerSize) {
    throw const GpException('BCFZ payload too short');
  }
  return Uint8List.sublistView(flat, headerSize, length);
}

/// Parses a raw `BCFS` filesystem [data] (header already stripped) into a
/// map of file name → contents.
///
/// The filesystem is a chain of 0x1000-byte sectors. A sector starting with
/// the little-endian int `2` is a file entry: a zero-terminated name at
/// +0x04 (max 127 bytes), the file size at +0x8C, and a zero-terminated list
/// of data-sector indices from +0x94 (each index × 0x1000 is the absolute
/// position of one content sector).
Map<String, Uint8List> bcfsFiles(Uint8List data) {
  const sectorSize = 0x1000;
  final files = <String, Uint8List>{};
  var offset = sectorSize;
  while (offset + 3 < data.length) {
    if (_int32At(data, offset) == 2) {
      final name = _stringAt(data, offset + 0x04, 127);
      final fileSize = _int32At(data, offset + 0x8C);
      final content = BytesBuilder(copy: false);
      var pointer = offset + 0x94;
      while (pointer + 3 < data.length) {
        final sector = _int32At(data, pointer);
        if (sector == 0) break;
        final start = sector * sectorSize;
        if (start >= data.length) break;
        final end = start + sectorSize > data.length
            ? data.length
            : start + sectorSize;
        content.add(Uint8List.sublistView(data, start, end));
        // The next entry sector comes after the last data sector.
        if (start > offset) offset = start;
        pointer += 4;
      }
      final bytes = content.takeBytes();
      files[name] = bytes.length > fileSize
          ? Uint8List.sublistView(bytes, 0, fileSize)
          : bytes;
    }
    offset += sectorSize;
  }
  return files;
}

int _int32At(Uint8List data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);

String _stringAt(Uint8List data, int offset, int maxLength) {
  final chars = <int>[];
  for (var i = 0; i < maxLength && offset + i < data.length; i++) {
    final code = data[offset + i];
    if (code == 0) break;
    chars.add(code);
  }
  return String.fromCharCodes(chars);
}

/// Thrown internally when the BCFZ bit stream ends mid-chunk.
class _EndOfStream implements Exception {
  const _EndOfStream();
}

/// Most-significant-bit-first reader over a byte buffer (the BCFZ stream is
/// not byte-aligned after the first flag bit).
class _BitReader {
  final Uint8List _data;
  int _byte = 0;
  int _bit = 0;

  _BitReader(this._data);

  int readBit() {
    if (_byte >= _data.length) throw const _EndOfStream();
    final value = (_data[_byte] >> (7 - _bit)) & 1;
    if (++_bit == 8) {
      _bit = 0;
      _byte++;
    }
    return value;
  }

  /// Reads [count] bits most-significant-first.
  int readBits(int count) {
    var value = 0;
    for (var i = count - 1; i >= 0; i--) {
      value |= readBit() << i;
    }
    return value;
  }

  /// Reads [count] bits least-significant-first (the encoding BCFZ uses for
  /// back-reference offset/length fields).
  int readBitsReversed(int count) {
    var value = 0;
    for (var i = 0; i < count; i++) {
      value |= readBit() << i;
    }
    return value;
  }

  int readByte() => readBits(8);

  /// Reads a little-endian 32-bit integer (bitwise, need not be byte-aligned).
  int readInt32() {
    final b0 = readByte(), b1 = readByte(), b2 = readByte(), b3 = readByte();
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
  }

  void skipBytes(int count) {
    for (var i = 0; i < count; i++) {
      readByte();
    }
  }
}
