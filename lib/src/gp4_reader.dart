import 'gp3_reader.dart';
import 'models.dart';

/// Reader for Guitar Pro 4 files. Extends [GP3File], overriding the parts of the
/// format that changed between GP3 and GP4.
class GP4File extends GP3File {
  GP4File(super.data);

  @override
  Song readSong() {
    final song = Song(tracks: <Track>[], measureHeaders: <MeasureHeader>[]);
    song.version = readVersion();
    song.versionTuple = versionTuple;
    song.clipboard = readClipboard();
    readInfo(song);
    tripletFeel = readBool() ? TripletFeel.eighth : TripletFeel.none;
    song.lyrics = readLyrics();
    song.tempo = readI32();
    song.key = KeySignature(readI32(), 0);
    readI8(); // octave
    final channels = readMidiChannels();
    final measureCount = readI32();
    final trackCount = readI32();
    annotateErrors<void>('reading', () {
      readMeasureHeaders(song, measureCount);
      readTracks(song, trackCount, channels);
      readMeasures(song);
    });
    return song;
  }

  Clipboard? readClipboard() {
    if (!isClipboard()) return null;
    final clipboard = Clipboard();
    clipboard.startMeasure = readI32();
    clipboard.stopMeasure = readI32();
    clipboard.startTrack = readI32();
    clipboard.stopTrack = readI32();
    return clipboard;
  }

  bool isClipboard() => version != null && version!.startsWith('CLIPBOARD');

  Lyrics readLyrics() {
    final lyrics = Lyrics();
    lyrics.trackChoice = readI32();
    for (final line in lyrics.lines) {
      line.startingMeasure = readI32();
      line.lyrics = readIntSizeString();
    }
    return lyrics;
  }

  @override
  void readNewChord(Chord chord) {
    chord.sharp = readBool();
    final intonation = chord.sharp! ? 'sharp' : 'flat';
    skip(3);
    chord.root = PitchClass(readU8(), intonation: intonation);
    chord.type = ChordType(readU8());
    chord.extension = ChordExtension(readU8());
    chord.bass = PitchClass(readI32(), intonation: intonation);
    chord.tonality = ChordAlteration.fromValue(readI32());
    chord.add = readBool();
    chord.name = readByteSizeString(22);
    chord.fifth = ChordAlteration.fromValue(readU8());
    chord.ninth = ChordAlteration.fromValue(readU8());
    chord.eleventh = ChordAlteration.fromValue(readU8());
    chord.firstFret = readI32();
    for (var i = 0; i < 7; i++) {
      final fret = readI32();
      if (i < chord.strings.length) chord.strings[i] = fret;
    }
    chord.barres = <Barre>[];
    final barresCount = readU8();
    final barreFrets = [for (var i = 0; i < 5; i++) readU8()];
    final barreStarts = [for (var i = 0; i < 5; i++) readU8()];
    final barreEnds = [for (var i = 0; i < 5; i++) readU8()];
    for (var i = 0; i < barresCount && i < 5; i++) {
      chord.barres.add(
        Barre(barreFrets[i], start: barreStarts[i], end: barreEnds[i]),
      );
    }
    chord.omissions = [for (var i = 0; i < 7; i++) readBool()];
    skip(1);
    chord.fingerings = [for (var i = 0; i < 7; i++) Fingering(readI8())];
    chord.show = readBool();
  }

  @override
  BeatEffect readBeatEffects(NoteEffect noteEffect) {
    final beatEffect = BeatEffect();
    final flags1 = readI8();
    final flags2 = readI8();
    beatEffect.vibrato = (flags1 & 0x02 != 0) || beatEffect.vibrato;
    beatEffect.fadeIn = flags1 & 0x10 != 0;
    if (flags1 & 0x20 != 0) {
      beatEffect.slapEffect = SlapEffect.fromValue(readI8());
    }
    if (flags2 & 0x04 != 0) beatEffect.tremoloBar = readTremoloBar();
    if (flags1 & 0x40 != 0) beatEffect.stroke = readBeatStroke();
    beatEffect.hasRasgueado = flags2 & 0x01 != 0;
    if (flags2 & 0x02 != 0) {
      beatEffect.pickStroke = BeatStrokeDirection.fromValue(readI8());
    }
    return beatEffect;
  }

  @override
  BendEffect? readTremoloBar() => readBend();

  @override
  MixTableChange readMixTableChange(Measure measure) {
    final tableChange = super.readMixTableChange(measure);
    readMixTableChangeFlags(tableChange);
    return tableChange;
  }

  int readMixTableChangeFlags(MixTableChange tableChange) {
    final flags = readI8();
    if (tableChange.volume != null) {
      tableChange.volume!.allTracks = flags & 0x01 != 0;
    }
    if (tableChange.balance != null) {
      tableChange.balance!.allTracks = flags & 0x02 != 0;
    }
    if (tableChange.chorus != null) {
      tableChange.chorus!.allTracks = flags & 0x04 != 0;
    }
    if (tableChange.reverb != null) {
      tableChange.reverb!.allTracks = flags & 0x08 != 0;
    }
    if (tableChange.phaser != null) {
      tableChange.phaser!.allTracks = flags & 0x10 != 0;
    }
    if (tableChange.tremolo != null) {
      tableChange.tremolo!.allTracks = flags & 0x20 != 0;
    }
    return flags;
  }

  @override
  NoteEffect readNoteEffects(Note note) {
    final noteEffect = note.effect;
    final flags1 = readI8();
    final flags2 = readI8();
    noteEffect.hammer = flags1 & 0x02 != 0;
    noteEffect.letRing = flags1 & 0x08 != 0;
    noteEffect.staccato = flags2 & 0x01 != 0;
    noteEffect.palmMute = flags2 & 0x02 != 0;
    noteEffect.vibrato = (flags2 & 0x40 != 0) || noteEffect.vibrato;
    if (flags1 & 0x01 != 0) noteEffect.bend = readBend();
    if (flags1 & 0x10 != 0) noteEffect.grace = readGrace();
    if (flags2 & 0x04 != 0) noteEffect.tremoloPicking = readTremoloPicking();
    if (flags2 & 0x08 != 0) noteEffect.slides = readSlides();
    if (flags2 & 0x10 != 0) noteEffect.harmonic = readHarmonic(note);
    if (flags2 & 0x20 != 0) noteEffect.trill = readTrill();
    return noteEffect;
  }

  TremoloPickingEffect readTremoloPicking() {
    final value = readI8();
    final tp = TremoloPickingEffect();
    tp.duration.value = fromTremoloValue(value);
    return tp;
  }

  int fromTremoloValue(int value) {
    switch (value) {
      case 1:
        return Duration.eighth;
      case 2:
        return Duration.sixteenth;
      case 3:
        return Duration.thirtySecond;
      default:
        return Duration.eighth;
    }
  }

  @override
  List<SlideType> readSlides() => <SlideType>[SlideType.fromValue(readI8())];

  HarmonicEffect readHarmonic(Note note) {
    final harmonicType = readI8();
    switch (harmonicType) {
      case 1:
        return const NaturalHarmonic();
      case 3:
        return const TappedHarmonic();
      case 4:
        return const PinchHarmonic();
      case 5:
        return const SemiHarmonic();
      case 15:
        return ArtificialHarmonic(
          PitchClass((note.realValue + 7) % 12),
          Octave.ottava,
        );
      case 17:
        return ArtificialHarmonic(
          PitchClass(note.realValue),
          Octave.quindicesima,
        );
      case 22:
        return ArtificialHarmonic(PitchClass(note.realValue), Octave.ottava);
      default:
        throw GpException('unknown harmonic type $harmonicType');
    }
  }

  TrillEffect readTrill() {
    final trill = TrillEffect();
    trill.fret = readI8();
    trill.duration.value = fromTrillPeriod(readI8());
    return trill;
  }

  int fromTrillPeriod(int period) {
    switch (period) {
      case 1:
        return Duration.sixteenth;
      case 2:
        return Duration.thirtySecond;
      case 3:
        return Duration.sixtyFourth;
      default:
        return Duration.sixteenth;
    }
  }
}
