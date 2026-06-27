import 'dart:typed_data';

import 'cp1252.dart';
import 'gp3_reader.dart';
import 'gp4_reader.dart';
import 'gp5_reader.dart';
import 'models.dart';

/// Maps the 30-byte version string at the head of a GP file to its version
/// tuple and the reader that understands it, ported from PyGuitarPro's
/// `io._GPFILES`.
class _VersionInfo {
  final List<int> tuple;
  final GP3File Function(Uint8List) make;
  const _VersionInfo(this.tuple, this.make);
}

final Map<String, _VersionInfo> _gpFiles = {
  'FICHIER GUITAR PRO v3.00': _VersionInfo([3, 0, 0], GP3File.new),
  'FICHIER GUITAR PRO v4.00': _VersionInfo([4, 0, 0], GP4File.new),
  'FICHIER GUITAR PRO v4.06': _VersionInfo([4, 0, 6], GP4File.new),
  'FICHIER GUITAR PRO L4.06': _VersionInfo([4, 0, 6], GP4File.new),
  'CLIPBOARD GUITAR PRO 4.0 [c6]': _VersionInfo([4, 0, 6], GP4File.new),
  'FICHIER GUITAR PRO v5.00': _VersionInfo([5, 0, 0], GP5File.new),
  'FICHIER GUITAR PRO v5.10': _VersionInfo([5, 1, 0], GP5File.new),
  'CLIPBOARD GP 5.0': _VersionInfo([5, 0, 0], GP5File.new),
  'CLIPBOARD GP 5.1': _VersionInfo([5, 1, 0], GP5File.new),
  'CLIPBOARD GP 5.2': _VersionInfo([5, 2, 0], GP5File.new),
};

/// Reads the byte-size version string at the start of [data] without consuming a
/// reader, so we can pick the right reader subclass.
String _peekVersion(Uint8List data) {
  if (data.isEmpty) throw const GpException('empty file');
  final size = data[0];
  if (1 + size > data.length) {
    throw const GpException('file too short to contain a version string');
  }
  return decodeCp1252(data.sublist(1, 1 + size));
}

/// Parses a Guitar Pro (GP3/GP4/GP5) file from its raw [bytes] and returns the
/// decoded [Song].
///
/// Throws [GpException] for unsupported versions (including the zip-based
/// GP6/GP7 `.gpx`/`.gp` formats) or malformed data.
Song parseGp(Uint8List bytes) {
  final versionString = _peekVersion(bytes);
  final info = _gpFiles[versionString];
  if (info == null) {
    throw GpException("unsupported version '$versionString'");
  }
  final reader = info.make(bytes);
  reader.readVersion(); // consume the 30-byte version header
  reader.versionTuple = info.tuple;
  return reader.readSong();
}
