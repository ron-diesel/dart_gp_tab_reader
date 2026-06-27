/// Decoding of the Windows-1252 (cp1252) charset that Guitar Pro uses to store
/// text. `dart:convert` ships `latin1` but not cp1252; the two agree everywhere
/// except for bytes 0x80–0x9F, where cp1252 maps a handful of typographic
/// characters that latin1 leaves as C1 control codes. This table covers exactly
/// that range; every other byte decodes to the same code point as its value.
library;

/// Code points for cp1252 bytes 0x80–0x9F. `0` marks an undefined slot, which we
/// fall back to decoding as the raw byte value (matching Python's behaviour of
/// keeping the C1 control code).
const List<int> _high = <int>[
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 0x80–0x87
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, // 0x88–0x8F
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 0x90–0x97
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, // 0x98–0x9F
];

/// Decodes [bytes] interpreted as cp1252 into a Dart string.
String decodeCp1252(List<int> bytes) {
  final codeUnits = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i] & 0xFF;
    codeUnits[i] = (b >= 0x80 && b <= 0x9F) ? _high[b - 0x80] : b;
  }
  return String.fromCharCodes(codeUnits);
}
