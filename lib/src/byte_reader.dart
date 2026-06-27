import 'dart:typed_data';

import 'cp1252.dart';
import 'models.dart';

/// Low-level binary reader for Guitar Pro files, a port of PyGuitarPro's
/// `iobase.GPFileBase` (read side only).
///
/// Guitar Pro stores multi-byte integers little-endian and strings in an 8-bit
/// charset (cp1252 by default). This class walks a [Uint8List] with a cursor,
/// exposing the same primitive readers PyGuitarPro uses so the GP3/4/5 readers
/// can be transcribed almost line for line.
class GpByteReader {
  GpByteReader(this.data);

  final Uint8List data;
  late final ByteData _view = ByteData.view(
    data.buffer,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  int _pos = 0;

  /// PyGuitarPro stores these as class attributes on `GPFileBase`; bends encode
  /// positions/values against them.
  static const int bendPosition = 60;
  static const int bendSemitone = 25;

  String? version;
  List<int>? versionTuple;

  // Error-location breadcrumbs, mirrored from PyGuitarPro so a parse failure can
  // report where in the song it happened.
  Track? currentTrack;
  int? currentMeasureNumber;
  int? currentVoiceNumber;
  int? currentBeatNumber;

  int get position => _pos;
  bool get atEnd => _pos >= data.lengthInBytes;

  void skip(int count) => _pos += count;

  int _ensure(int count) {
    if (_pos + count > data.lengthInBytes) {
      throw const GpException('unexpected end of file');
    }
    final at = _pos;
    _pos += count;
    return at;
  }

  /// Reads a signed 8-bit integer.
  int readI8({int? defaultValue}) {
    if (_pos + 1 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getInt8(_ensure(1));
  }

  /// Reads an unsigned 8-bit integer.
  int readU8({int? defaultValue}) {
    if (_pos + 1 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getUint8(_ensure(1));
  }

  /// Reads an 8-bit boolean.
  bool readBool({bool? defaultValue}) {
    if (_pos + 1 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getUint8(_ensure(1)) != 0;
  }

  /// Reads a signed little-endian 16-bit integer.
  int readI16({int? defaultValue}) {
    if (_pos + 2 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getInt16(_ensure(2), Endian.little);
  }

  /// Reads a signed little-endian 32-bit integer.
  int readI32({int? defaultValue}) {
    if (_pos + 4 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getInt32(_ensure(4), Endian.little);
  }

  /// Reads a little-endian 64-bit float.
  double readF64({double? defaultValue}) {
    if (_pos + 8 > data.lengthInBytes) {
      if (defaultValue != null) return defaultValue;
      throw const GpException('unexpected end of file');
    }
    return _view.getFloat64(_ensure(8), Endian.little);
  }

  List<int> _readBytes(int count) {
    final at = _ensure(count);
    return data.sublist(at, at + count);
  }

  /// Reads a length byte followed by [count] character bytes, returning the
  /// first `length` of them decoded as cp1252.
  String readByteSizeString(int count) {
    if (count > 255) {
      throw ArgumentError('count must be <= 255');
    }
    final size = readU8();
    final bytes = _readBytes(count);
    return decodeCp1252(bytes.sublist(0, size));
  }

  /// Reads a 4-byte length followed by exactly that many character bytes.
  String readIntSizeString() {
    final count = readI32();
    return decodeCp1252(_readBytes(count));
  }

  /// Reads a 4-byte length followed by a byte-size string of `length - 1`.
  String readIntByteSizeString() {
    final count = readI32();
    return readByteSizeString(count - 1);
  }

  /// Reads (and caches) the 30-byte version string at the head of the file.
  String readVersion() {
    return version ??= readByteSizeString(30);
  }

  /// Runs [body], decorating any thrown error with the current parse location,
  /// matching PyGuitarPro's `annotateErrors` context manager.
  T annotateErrors<T>(String action, T Function() body) {
    currentTrack = null;
    currentMeasureNumber = null;
    currentVoiceNumber = null;
    currentBeatNumber = null;
    try {
      return body();
    } catch (err) {
      final location = _currentLocation();
      if (location.isEmpty) rethrow;
      throw GpException(
        '$action ${location.join(', ')}, got ${err.runtimeType}: $err',
      );
    } finally {
      currentTrack = null;
      currentMeasureNumber = null;
      currentVoiceNumber = null;
      currentBeatNumber = null;
    }
  }

  List<String> _currentLocation() {
    final location = <String>[];
    if (currentTrack != null) location.add('track ${currentTrack!.number}');
    if (currentMeasureNumber != null) {
      location.add('measure $currentMeasureNumber');
    }
    if (currentVoiceNumber != null) location.add('voice $currentVoiceNumber');
    if (currentBeatNumber != null) location.add('beat $currentBeatNumber');
    return location;
  }
}
