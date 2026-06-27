import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart';
import 'package:test/test.dart';

/// Flattens a parsed [Song] into `[measure, voice, beat, string, fret, type]`
/// rows, matching the reference dump produced by PyGuitarPro (`dump_ref.py`).
List<List<int>> flattenNotes(Track track) {
  final notes = <List<int>>[];
  for (var mi = 0; mi < track.measures.length; mi++) {
    final measure = track.measures[mi];
    for (var vi = 0; vi < measure.voices.length; vi++) {
      final voice = measure.voices[vi];
      for (var bi = 0; bi < voice.beats.length; bi++) {
        for (final note in voice.beats[bi].notes) {
          notes.add([mi, vi, bi, note.string, note.value, note.type.value]);
        }
      }
    }
  }
  return notes;
}

void main() {
  final fixturesDir = Directory('test/fixtures');
  final reference =
      jsonDecode(File('test/fixtures/_reference.json').readAsStringSync())
          as Map<String, dynamic>;

  group('parses GP fixtures identically to PyGuitarPro', () {
    for (final entry in reference.entries) {
      final fileName = entry.key;
      final expected = entry.value as Map<String, dynamic>;
      if (expected.containsKey('error')) continue;

      test(fileName, () {
        final bytes = File('${fixturesDir.path}/$fileName').readAsBytesSync();
        final song = parseGp(bytes);

        expect(song.title, expected['title'], reason: 'title');
        expect(song.artist, expected['artist'], reason: 'artist');
        expect(song.album, expected['album'], reason: 'album');
        expect(song.tempo, expected['tempo'], reason: 'tempo');
        expect(
          song.measureHeaders.length,
          expected['measureCount'],
          reason: 'measure count',
        );

        final expectedTracks = expected['tracks'] as List<dynamic>;
        expect(
          song.tracks.length,
          expectedTracks.length,
          reason: 'track count',
        );

        for (var t = 0; t < song.tracks.length; t++) {
          final track = song.tracks[t];
          final exp = expectedTracks[t] as Map<String, dynamic>;
          expect(track.name, exp['name'], reason: 'track $t name');
          expect(
            track.strings.map((s) => s.value).toList(),
            (exp['strings'] as List).cast<int>(),
            reason: 'track $t tuning',
          );

          final got = flattenNotes(track);
          final expNotes = (exp['notes'] as List)
              .map((e) => (e as List).cast<int>())
              .toList();
          expect(got.length, exp['noteCount'], reason: 'track $t note count');
          expect(got, expNotes, reason: 'track $t note data');
        }
      });
    }
  });

  test('rejects unsupported version strings', () {
    // A bogus byte-size version header that maps to no known reader.
    final bogus = Uint8List.fromList(<int>[
      5,
      ...'BOGUS'.codeUnits,
      ...List.filled(30, 0),
    ]);
    expect(() => parseGp(bogus), throwsA(isA<GpException>()));
  });
}
