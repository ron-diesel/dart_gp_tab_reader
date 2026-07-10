import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart';
import 'package:dart_gp_tab_reader/src/gpx_reader.dart'
    show bcfsFiles, decompressBcfz;
import 'package:test/test.dart';

/// A minimal GP6-flavoured score.gpif: metadata under GP6 element names
/// (`GeneralMidi`, track-level properties) and a percussion note encoded as
/// an element/variation pair instead of GP7's articulation index.
const String _gpif = '''
<?xml version="1.0" encoding="utf-8"?>
<GPIF>
  <Score><Title><![CDATA[GPX Song]]></Title></Score>
  <MasterTrack>
    <Tracks>0 1</Tracks>
    <Automations>
      <Automation>
        <Type>Tempo</Type><Bar>0</Bar><Position>0</Position><Value>90 2</Value>
      </Automation>
    </Automations>
  </MasterTrack>
  <Tracks>
    <Track id="0">
      <Name><![CDATA[Guitar]]></Name>
      <GeneralMidi><Program>29</Program><PrimaryChannel>0</PrimaryChannel></GeneralMidi>
      <Properties>
        <Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property>
      </Properties>
    </Track>
    <Track id="1">
      <Name><![CDATA[Drums]]></Name>
      <GeneralMidi table="Percussion"><Program>0</Program><PrimaryChannel>9</PrimaryChannel></GeneralMidi>
    </Track>
  </Tracks>
  <MasterBars>
    <MasterBar><Time>4/4</Time><Bars>0 1</Bars></MasterBar>
  </MasterBars>
  <Bars>
    <Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar>
    <Bar id="1"><Voices>1 -1 -1 -1</Voices></Bar>
  </Bars>
  <Voices>
    <Voice id="0"><Beats>0</Beats></Voice>
    <Voice id="1"><Beats>1</Beats></Voice>
  </Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0"/><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Notes>1</Notes></Beat>
  </Beats>
  <Notes>
    <Note id="0">
      <Properties>
        <Property name="String"><String>2</String></Property>
        <Property name="Fret"><Fret>3</Fret></Property>
      </Properties>
    </Note>
    <Note id="1">
      <Properties>
        <Property name="Element"><Element>10</Element></Property>
        <Property name="Variation"><Variation>0</Variation></Property>
      </Properties>
    </Note>
  </Notes>
  <Rhythms>
    <Rhythm id="0"><NoteValue>Whole</NoteValue></Rhythm>
  </Rhythms>
</GPIF>
''';

const int _sector = 0x1000;

/// Builds a raw BCFS filesystem (no 4-byte header): an empty first sector, a
/// file entry for `score.gpif` in the second, and its content in the third.
Uint8List buildBcfs(List<int> content) {
  final data = Uint8List(3 * _sector);
  data.fillRange(0, _sector, 0xFF);
  // File entry at sector 1.
  final entry = ByteData.sublistView(data, _sector);
  entry.setUint32(0, 2, Endian.little); // entryType = file
  data.setRange(_sector + 0x04, _sector + 0x04 + 10, ascii.encode('score.gpif'));
  entry.setUint32(0x8C, content.length, Endian.little); // fileSize
  entry.setUint32(0x94, 2, Endian.little); // data in sector 2, then 0-end
  data.setRange(2 * _sector, 2 * _sector + content.length, content);
  return data;
}

/// Bit-level writer mirroring the BCFZ reader: bits go most-significant-first
/// into each byte.
class BitWriter {
  final List<int> bytes = [];
  int _current = 0;
  int _filled = 0;

  void writeBit(int bit) {
    _current = (_current << 1) | (bit & 1);
    if (++_filled == 8) {
      bytes.add(_current);
      _current = 0;
      _filled = 0;
    }
  }

  /// Writes [count] bits of [value] most-significant-first.
  void writeBits(int value, int count) {
    for (var i = count - 1; i >= 0; i--) {
      writeBit((value >> i) & 1);
    }
  }

  /// Writes [count] bits of [value] least-significant-first (the encoding of
  /// back-reference offset/size fields).
  void writeBitsReversed(int value, int count) {
    for (var i = 0; i < count; i++) {
      writeBit((value >> i) & 1);
    }
  }

  Uint8List finish() {
    while (_filled != 0) {
      writeBit(0);
    }
    return Uint8List.fromList(bytes);
  }
}

/// Compresses [payload] into a BCFZ stream using raw chunks only.
Uint8List buildBcfz(List<int> payload) {
  final w = BitWriter();
  for (final b in ascii.encode('BCFZ')) {
    w.writeBits(b, 8);
  }
  // 32-bit little-endian expected length.
  for (var i = 0; i < 4; i++) {
    w.writeBits((payload.length >> (8 * i)) & 0xFF, 8);
  }
  for (var i = 0; i < payload.length; i += 3) {
    final size = (payload.length - i) < 3 ? payload.length - i : 3;
    w.writeBit(0); // raw chunk
    w.writeBitsReversed(size, 2);
    for (var j = 0; j < size; j++) {
      w.writeBits(payload[i + j], 8);
    }
  }
  return w.finish();
}

void main() {
  group('BCFZ decompressor', () {
    test('decodes raw chunks', () {
      final payload = [...ascii.encode('BCFS'), ...ascii.encode('hello world')];
      expect(decompressBcfz(buildBcfz(payload)), ascii.encode('hello world'));
    });

    test('decodes back-references', () {
      // "BCFS" + "abc", then a back-reference copying "abc" again.
      final w = BitWriter();
      final payload = [...ascii.encode('BCFS'), ...ascii.encode('abc')];
      for (final b in ascii.encode('BCFZ')) {
        w.writeBits(b, 8);
      }
      for (var i = 0; i < 4; i++) {
        w.writeBits((10 >> (8 * i)) & 0xFF, 8); // expect 4 + 3 + 3 bytes
      }
      for (var i = 0; i < payload.length; i += 3) {
        final size = (payload.length - i) < 3 ? payload.length - i : 3;
        w.writeBit(0);
        w.writeBitsReversed(size, 2);
        for (var j = 0; j < size; j++) {
          w.writeBits(payload[i + j], 8);
        }
      }
      w.writeBit(1); // back-reference chunk
      w.writeBits(4, 4); // word size: 4 bits
      w.writeBitsReversed(3, 4); // offset 3 (from end: "abc")
      w.writeBitsReversed(3, 4); // size 3
      expect(decompressBcfz(w.finish()), ascii.encode('abcabc'));
    });
  });

  test('BCFS filesystem parser finds files across sectors', () {
    final files = bcfsFiles(buildBcfs(ascii.encode('<GPIF/>')));
    expect(files.keys, ['score.gpif']);
    expect(ascii.decode(files['score.gpif']!), '<GPIF/>');
  });

  group('parseGp on synthetic .gpx', () {
    final gpifBytes = utf8.encode(_gpif);
    final bcfs = Uint8List.fromList(
        [...ascii.encode('BCFS'), ...buildBcfs(gpifBytes)]);
    final bcfz = buildBcfz([...ascii.encode('BCFS'), ...buildBcfs(gpifBytes)]);

    for (final (label, bytes) in [('BCFS', bcfs), ('BCFZ', bcfz)]) {
      test('parses an uncompressed/compressed container ($label)', () {
        final song = parseGp(bytes);
        expect(song.title, 'GPX Song');
        expect(song.tempo, 90);
        expect(song.tracks, hasLength(2));
        // GP6-style track data: GeneralMidi program + track-level tuning.
        expect(song.tracks[0].channel.instrument, 29);
        expect([for (final s in song.tracks[0].strings) s.value],
            [64, 59, 55, 50, 45, 40]);
        final note = song.tracks[0].measures[0].voices[0].beats[0].notes.single;
        expect(note.string, 4); // GPIF string 2 of 6 → model number 4
        expect(note.value, 3);
        // GP6 percussion: element 10 / variation 0 = closed hi-hat (GM 42).
        expect(song.tracks[1].isPercussionTrack, isTrue);
        final drum = song.tracks[1].measures[0].voices[0].beats[0].notes.single;
        expect(drum.value, 42);
      });
    }
  });
}
