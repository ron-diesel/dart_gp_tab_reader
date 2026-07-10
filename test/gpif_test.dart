import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart';
import 'package:test/test.dart';

/// A small hand-written score.gpif exercising the GPIF features the reader
/// maps: metadata, tempo/sound automations, tunings, capo, channel-strip
/// volume/pan, percussion articulations, deduplicated beats, grace-beat
/// skipping, rests, ties, dead/palm-muted notes, hammer-ons, slides, vibrato
/// and dynamics.
const String _gpif = '''
<?xml version="1.0" encoding="utf-8"?>
<GPIF>
  <GPVersion>7.6.0</GPVersion>
  <Score>
    <Title><![CDATA[Test Song]]></Title>
    <Artist><![CDATA[Tester]]></Artist>
    <Album><![CDATA[Fixtures]]></Album>
  </Score>
  <MasterTrack>
    <Tracks>0 1</Tracks>
    <Automations>
      <Automation>
        <Type>Tempo</Type><Linear>false</Linear><Bar>0</Bar>
        <Position>0</Position><Value>120 2</Value>
      </Automation>
      <Automation>
        <Type>Tempo</Type><Linear>false</Linear><Bar>2</Bar>
        <Position>0</Position><Value>70 3</Value>
      </Automation>
    </Automations>
  </MasterTrack>
  <Tracks>
    <Track id="0">
      <Name><![CDATA[Guitar]]></Name>
      <Sounds>
        <Sound>
          <Name><![CDATA[Clean]]></Name><Path>P</Path><Role>User</Role>
          <MIDI><Program>27</Program></MIDI>
        </Sound>
        <Sound>
          <Name><![CDATA[Dist]]></Name><Path>P</Path><Role>User</Role>
          <MIDI><Program>30</Program></MIDI>
        </Sound>
      </Sounds>
      <Automations>
        <Automation>
          <Type>Sound</Type><Bar>1</Bar><Position>0</Position>
          <Value><![CDATA[P;Dist;User]]></Value>
        </Automation>
      </Automations>
      <RSE>
        <ChannelStrip>
          <Parameters>0 0 0 0 0 0 0 0 0 0 0 0.25 0.5 0 0 0</Parameters>
        </ChannelStrip>
      </RSE>
      <Staves>
        <Staff>
          <Properties>
            <Property name="CapoFret"><Fret>2</Fret></Property>
            <Property name="Tuning"><Pitches>40 45 50 55 59 64</Pitches></Property>
          </Properties>
        </Staff>
      </Staves>
    </Track>
    <Track id="1">
      <Name><![CDATA[Drums]]></Name>
      <InstrumentSet>
        <Type>drumKit</Type>
        <Elements><Element><Articulations>
          <Articulation><OutputMidiNumber>36</OutputMidiNumber></Articulation>
          <Articulation><OutputMidiNumber>38</OutputMidiNumber></Articulation>
        </Articulations></Element></Elements>
      </InstrumentSet>
      <Sounds>
        <Sound>
          <Name><![CDATA[Kit]]></Name><Path>D</Path><Role>User</Role>
          <MIDI><Program>0</Program></MIDI>
        </Sound>
      </Sounds>
    </Track>
  </Tracks>
  <MasterBars>
    <MasterBar><Time>4/4</Time><Bars>0 3</Bars></MasterBar>
    <MasterBar><Time>3/4</Time><Bars>1 4</Bars></MasterBar>
    <MasterBar><Time>4/4</Time><Bars>2 5</Bars></MasterBar>
  </MasterBars>
  <Bars>
    <Bar id="0"><Voices>0 -1 -1 -1</Voices></Bar>
    <Bar id="1"><Voices>1 -1 -1 -1</Voices></Bar>
    <Bar id="2"><Voices>2 -1 -1 -1</Voices></Bar>
    <Bar id="3"><Voices>3 -1 -1 -1</Voices></Bar>
    <Bar id="4"><Voices>4 -1 -1 -1</Voices></Bar>
    <Bar id="5"><Voices>5 -1 -1 -1</Voices></Bar>
  </Bars>
  <Voices>
    <Voice id="0"><Beats>0 1 9 2 3</Beats></Voice>
    <Voice id="1"><Beats>4 4 4</Beats></Voice>
    <Voice id="2"><Beats>5 6</Beats></Voice>
    <Voice id="3"><Beats>7 7 7 7</Beats></Voice>
    <Voice id="4"><Beats>8 8 8</Beats></Voice>
    <Voice id="5"><Beats>7 8 7 8</Beats></Voice>
  </Voices>
  <Beats>
    <Beat id="0"><Rhythm ref="0"/><Dynamic>MF</Dynamic><Notes>0</Notes></Beat>
    <Beat id="1"><Rhythm ref="0"/><Dynamic>F</Dynamic><Notes>1 2</Notes></Beat>
    <Beat id="2"><Rhythm ref="0"/><Dynamic>F</Dynamic></Beat>
    <Beat id="3"><Rhythm ref="0"/><Dynamic>F</Dynamic><Notes>3</Notes></Beat>
    <Beat id="4"><Rhythm ref="0"/><Dynamic>F</Dynamic><Notes>4</Notes></Beat>
    <Beat id="5"><Rhythm ref="1"/><Dynamic>F</Dynamic><Notes>5</Notes></Beat>
    <Beat id="6"><Rhythm ref="1"/><Dynamic>F</Dynamic><Notes>6</Notes></Beat>
    <Beat id="7"><Rhythm ref="0"/><Dynamic>F</Dynamic><Notes>7</Notes></Beat>
    <Beat id="8"><Rhythm ref="0"/><Dynamic>F</Dynamic><Notes>8</Notes></Beat>
    <Beat id="9">
      <GraceNotes>BeforeBeat</GraceNotes>
      <Rhythm ref="2"/><Dynamic>F</Dynamic><Notes>4</Notes>
    </Beat>
  </Beats>
  <Notes>
    <Note id="0">
      <Properties>
        <Property name="String"><String>0</String></Property>
        <Property name="Fret"><Fret>0</Fret></Property>
        <Property name="Midi"><Number>40</Number></Property>
      </Properties>
    </Note>
    <Note id="1">
      <Properties>
        <Property name="String"><String>1</String></Property>
        <Property name="Fret"><Fret>2</Fret></Property>
        <Property name="PalmMuted"><Enable/></Property>
      </Properties>
    </Note>
    <Note id="2">
      <Properties>
        <Property name="String"><String>2</String></Property>
        <Property name="Fret"><Fret>2</Fret></Property>
        <Property name="HopoOrigin"><Enable/></Property>
      </Properties>
    </Note>
    <Note id="3">
      <Properties>
        <Property name="String"><String>3</String></Property>
        <Property name="Fret"><Fret>5</Fret></Property>
        <Property name="Muted"><Enable/></Property>
        <Property name="Slide"><Flags>2</Flags></Property>
      </Properties>
    </Note>
    <Note id="4">
      <Properties>
        <Property name="String"><String>5</String></Property>
        <Property name="Fret"><Fret>5</Fret></Property>
      </Properties>
    </Note>
    <Note id="5">
      <Properties>
        <Property name="String"><String>3</String></Property>
        <Property name="Fret"><Fret>7</Fret></Property>
      </Properties>
      <Tie origin="true" destination="false"/>
    </Note>
    <Note id="6">
      <Properties>
        <Property name="String"><String>3</String></Property>
        <Property name="Fret"><Fret>7</Fret></Property>
      </Properties>
      <Tie origin="false" destination="true"/>
      <Vibrato>Slight</Vibrato>
    </Note>
    <Note id="7"><InstrumentArticulation>0</InstrumentArticulation></Note>
    <Note id="8"><InstrumentArticulation>1</InstrumentArticulation></Note>
  </Notes>
  <Rhythms>
    <Rhythm id="0"><NoteValue>Quarter</NoteValue></Rhythm>
    <Rhythm id="1"><NoteValue>Half</NoteValue></Rhythm>
    <Rhythm id="2"><NoteValue>16th</NoteValue></Rhythm>
  </Rhythms>
</GPIF>
''';

/// Packs [gpif] into an in-memory GP7-style zip (`Content/score.gpif`).
Uint8List zipGp(String gpif) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('Content/score.gpif', gpif));
  return ZipEncoder().encodeBytes(archive);
}

void main() {
  const q = Duration.quarterTime; // 960 ticks per quarter

  group('GPIF (.gp) reader', () {
    final song = parseGp(zipGp(_gpif));
    final guitar = song.tracks[0];
    final drums = song.tracks[1];

    test('routes zip bytes through parseGp and reads metadata', () {
      expect(song.title, 'Test Song');
      expect(song.artist, 'Tester');
      expect(song.album, 'Fixtures');
      expect(song.versionTuple, [7, 6, 0]);
      expect(song.tempo, 120);
    });

    test('reads tracks, tuning, capo and mixer settings', () {
      expect(song.tracks, hasLength(2));
      expect(guitar.name, 'Guitar');
      // Model strings are numbered 1..N from the highest-pitched string.
      expect([for (final s in guitar.strings) s.value], [64, 59, 55, 50, 45, 40]);
      expect(guitar.offset, 2); // capo
      expect(guitar.channel.instrument, 27); // first <Sound> program
      expect(guitar.channel.balance, 32); // 0.25 * 127
      expect(guitar.channel.volume, 64); // 0.5 * 127
      expect(guitar.isPercussionTrack, isFalse);
      expect(drums.isPercussionTrack, isTrue);
      expect(drums.channel.channel, MidiChannel.defaultPercussionChannel);
    });

    test('lays out measures and beat ticks (first measure starts at 960)', () {
      expect(song.measureHeaders, hasLength(3));
      expect(song.measureHeaders[0].start, q);
      expect(song.measureHeaders[1].start, q + 4 * q); // after a 4/4 bar
      expect(song.measureHeaders[1].length, 3 * q); // 3/4
      expect(song.measureHeaders[2].start, q + 4 * q + 3 * q);

      final beats = guitar.measures[0].voices[0].beats;
      // The grace beat between beats 1 and 2 is an ornament and is skipped.
      expect(beats, hasLength(4));
      expect([for (final b in beats) b.start], [q, 2 * q, 3 * q, 4 * q]);
    });

    test('materialises deduplicated beat references as fresh beats', () {
      final beats = guitar.measures[1].voices[0].beats;
      expect(beats, hasLength(3)); // "4 4 4" — same element three times
      expect([for (final b in beats) b.start], [5 * q, 6 * q, 7 * q]);
      expect(identical(beats[0], beats[1]), isFalse);
    });

    test('maps rests, note kinds, techniques and dynamics', () {
      final beats = guitar.measures[0].voices[0].beats;
      expect(beats[0].notes.single.velocity, 79); // MF
      expect(beats[0].notes.single.string, 6); // GPIF string 0 = low E
      expect(beats[0].notes.single.realValue, 40);
      expect(beats[1].notes[0].effect.palmMute, isTrue);
      expect(beats[1].notes[0].velocity, 95); // F
      expect(beats[1].notes[1].effect.hammer, isTrue);
      expect(beats[2].status, BeatStatus.rest);
      expect(beats[3].notes.single.type, NoteType.dead);
      expect(beats[3].notes.single.effect.slides, [SlideType.legatoSlideTo]);

      final tied = guitar.measures[2].voices[0].beats;
      expect(tied[0].notes.single.type, NoteType.normal); // tie origin
      expect(tied[1].notes.single.type, NoteType.tie); // tie destination
      expect(tied[1].notes.single.effect.vibrato, isTrue);
    });

    test('attaches tempo and sound automations as mix-table changes', () {
      // Sound switch (program 30) on the first beat of bar 1.
      final barOne = guitar.measures[1].voices[0].beats.first;
      expect(barOne.effect.mixTableChange?.instrument?.value, 30);
      // Mid-song tempo: 70 dotted-quarter = 105 quarter BPM, on bar 2.
      final barTwo = guitar.measures[2].voices[0].beats.first;
      expect(barTwo.effect.mixTableChange?.tempo?.value, 105);
    });

    test('maps percussion notes through the articulation table', () {
      final kick = drums.measures[0].voices[0].beats.first.notes.single;
      expect(kick.value, 36);
      expect(kick.string, 0);
      final barTwo = drums.measures[2].voices[0].beats;
      expect([for (final b in barTwo) b.notes.single.value], [36, 38, 36, 38]);
    });
  });

  test('parseGpif reads bare score.gpif XML', () {
    final song = parseGpif(Uint8List.fromList(utf8.encode(_gpif)));
    expect(song.title, 'Test Song');
  });

  test('routes GP6 .gpx (BCFZ) magic to the gpx reader', () {
    // An empty BCFZ payload decompresses to nothing → container error.
    final bytes = Uint8List.fromList([...utf8.encode('BCFZ'), 0, 0, 0, 0]);
    expect(
      () => parseGp(bytes),
      throwsA(isA<GpException>()
          .having((e) => e.toString(), 'message', contains('BCFZ'))),
    );
  });

  test('rejects a zip without score.gpif', () {
    final archive = Archive()..addFile(ArchiveFile.string('foo.txt', 'hi'));
    expect(() => parseGp(ZipEncoder().encodeBytes(archive)),
        throwsA(isA<GpException>()));
  });
}
