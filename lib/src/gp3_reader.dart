import 'byte_reader.dart';
import 'models.dart';

/// Reader for Guitar Pro 3 files. Ported from PyGuitarPro's `gp3.GP3File`
/// (read side only). GP4 and GP5 readers subclass this and override the parts
/// that differ.
class GP3File extends GpByteReader {
  GP3File(super.data);

  TripletFeel tripletFeel = TripletFeel.none;

  /// Reads the whole song: score info, tempo, key, channels, headers, tracks,
  /// measures.
  Song readSong() {
    final song = Song(tracks: <Track>[], measureHeaders: <MeasureHeader>[]);
    song.version = readVersion();
    song.versionTuple = versionTuple;
    readInfo(song);
    tripletFeel = readBool() ? TripletFeel.eighth : TripletFeel.none;
    song.tempo = readI32();
    song.key = KeySignature(readI32(), 0);
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

  void readInfo(Song song) {
    song.title = readIntByteSizeString();
    song.subtitle = readIntByteSizeString();
    song.artist = readIntByteSizeString();
    song.album = readIntByteSizeString();
    song.words = readIntByteSizeString();
    song.music = song.words;
    song.copyright = readIntByteSizeString();
    song.tab = readIntByteSizeString();
    song.instructions = readIntByteSizeString();
    final notesCount = readI32();
    song.notice = <String>[];
    for (var i = 0; i < notesCount; i++) {
      song.notice.add(readIntByteSizeString());
    }
  }

  List<MidiChannel> readMidiChannels() {
    final channels = <MidiChannel>[];
    for (var i = 0; i < 64; i++) {
      final newChannel = MidiChannel();
      newChannel.channel = i;
      newChannel.effectChannel = i;
      var instrument = readI32();
      if (newChannel.isPercussionChannel && instrument == -1) instrument = 0;
      newChannel.instrument = instrument;
      newChannel.volume = toChannelShort(readI8());
      newChannel.balance = toChannelShort(readI8());
      newChannel.chorus = toChannelShort(readI8());
      newChannel.reverb = toChannelShort(readI8());
      newChannel.phaser = toChannelShort(readI8());
      newChannel.tremolo = toChannelShort(readI8());
      channels.add(newChannel);
      skip(2); // backward compat with 3.0
    }
    return channels;
  }

  int toChannelShort(int data) {
    final value = ((data << 3) - 1).clamp(-1, 32767);
    return value + 1;
  }

  void readMeasureHeaders(Song song, int measureCount) {
    MeasureHeader? previous;
    for (var number = 1; number <= measureCount; number++) {
      currentMeasureNumber = number;
      final header = readMeasureHeader(number, song, previous);
      song.addMeasureHeader(header);
      previous = header;
    }
    currentMeasureNumber = null;
  }

  MeasureHeader readMeasureHeader(
    int number,
    Song song, [
    MeasureHeader? previous,
  ]) {
    final flags = readU8();
    final header = MeasureHeader();
    header.number = number;
    header.start = 0;
    header.tripletFeel = tripletFeel;
    if (flags & 0x01 != 0) {
      header.timeSignature.numerator = readI8();
    } else {
      header.timeSignature.numerator = previous!.timeSignature.numerator;
    }
    if (flags & 0x02 != 0) {
      header.timeSignature.denominator.value = readI8();
    } else {
      header.timeSignature.denominator.value =
          previous!.timeSignature.denominator.value;
    }
    header.isRepeatOpen = flags & 0x04 != 0;
    if (flags & 0x08 != 0) header.repeatClose = readI8();
    if (flags & 0x10 != 0) {
      header.repeatAlternative = readRepeatAlternative(song.measureHeaders);
    }
    if (flags & 0x20 != 0) header.marker = readMarker(header);
    if (flags & 0x40 != 0) {
      final root = readI8();
      final type = readI8();
      header.keySignature = KeySignature(root, type);
    } else if (header.number > 1) {
      header.keySignature = previous!.keySignature;
    }
    header.hasDoubleBar = flags & 0x80 != 0;
    return header;
  }

  int readRepeatAlternative(List<MeasureHeader> measureHeaders) {
    final value = readU8();
    var existingAlternatives = 0;
    for (final header in measureHeaders.reversed) {
      if (header.isRepeatOpen) break;
      existingAlternatives |= header.repeatAlternative;
    }
    return ((1 << value) - 1) ^ existingAlternatives;
  }

  Marker readMarker(MeasureHeader header) {
    final marker = Marker();
    marker.title = readIntByteSizeString();
    marker.color = readColor();
    return marker;
  }

  Color readColor() {
    final r = readU8();
    final g = readU8();
    final b = readU8();
    skip(1);
    return Color(r, g, b);
  }

  void readTracks(Song song, int trackCount, List<MidiChannel> channels) {
    for (var i = 0; i < trackCount; i++) {
      final track = Track(
        song,
        number: i + 1,
        strings: <GuitarString>[],
        measures: <Measure>[],
      );
      currentTrack = track;
      readTrack(track, channels);
      song.tracks.add(track);
    }
    currentTrack = null;
  }

  void readTrack(Track track, List<MidiChannel> channels) {
    final flags = readU8();
    track.isPercussionTrack = flags & 0x01 != 0;
    track.is12StringedGuitarTrack = flags & 0x02 != 0;
    track.isBanjoTrack = flags & 0x04 != 0;
    track.name = readByteSizeString(40);
    final stringCount = readI32();
    for (var i = 0; i < 7; i++) {
      final iTuning = readI32();
      if (stringCount > i) {
        track.strings.add(GuitarString(i + 1, iTuning));
      }
    }
    track.port = readI32();
    track.channel = readChannel(channels);
    if (track.channel.channel == 9) track.isPercussionTrack = true;
    track.fretCount = readI32();
    track.offset = readI32();
    track.color = readColor();
  }

  MidiChannel readChannel(List<MidiChannel> channels) {
    final index = readI32() - 1;
    final effectChannel = readI32() - 1;
    if (index >= 0 && index < channels.length) {
      final trackChannel = channels[index];
      if (trackChannel.instrument < 0) trackChannel.instrument = 0;
      if (!trackChannel.isPercussionChannel) {
        trackChannel.effectChannel = effectChannel;
      }
      return trackChannel;
    }
    return MidiChannel();
  }

  void readMeasures(Song song) {
    num start = Duration.quarterTime;
    for (final header in song.measureHeaders) {
      header.start = start;
      for (final track in song.tracks) {
        currentTrack = track;
        final measure = Measure(track, header);
        currentMeasureNumber = measure.number;
        track.measures.add(measure);
        readMeasure(measure);
      }
      start += header.length;
    }
    currentTrack = null;
    currentMeasureNumber = null;
  }

  void readMeasure(Measure measure) {
    final start = measure.start;
    final voice = measure.voices[0];
    currentVoiceNumber = 1;
    readVoice(start, voice);
    currentVoiceNumber = null;
  }

  void readVoice(num start, Voice voice) {
    final beats = readI32();
    var s = start;
    for (var beat = 0; beat < beats; beat++) {
      currentBeatNumber = beat + 1;
      s += readBeat(s, voice);
    }
    currentBeatNumber = null;
  }

  num readBeat(num start, Voice voice) {
    final flags = readU8();
    final beat = getBeat(voice, start);
    if (flags & 0x40 != 0) {
      beat.status = BeatStatus.fromValue(readU8());
    } else {
      beat.status = BeatStatus.normal;
    }
    final duration = readDuration(flags);
    final noteEffect = NoteEffect();
    if (flags & 0x02 != 0) {
      beat.effect.chord = readChord(voice.measure.track.strings.length);
    }
    if (flags & 0x04 != 0) beat.text = readIntByteSizeString();
    if (flags & 0x08 != 0) {
      final chord = beat.effect.chord;
      beat.effect = readBeatEffects(noteEffect);
      beat.effect.chord = chord;
    }
    if (flags & 0x10 != 0) {
      beat.effect.mixTableChange = readMixTableChange(voice.measure);
    }
    readNotes(voice.measure.track, beat, duration, noteEffect);
    return beat.status == BeatStatus.empty ? 0 : duration.time;
  }

  Beat getBeat(Voice voice, num start) {
    for (final beat in voice.beats.reversed) {
      if (beat.start == start) return beat;
    }
    final newBeat = Beat(voice);
    newBeat.start = start;
    voice.beats.add(newBeat);
    return newBeat;
  }

  Duration readDuration(int flags) {
    final duration = Duration();
    duration.value = 1 << (readI8() + 2);
    duration.isDotted = flags & 0x01 != 0;
    if (flags & 0x20 != 0) {
      final iTuplet = readI32();
      switch (iTuplet) {
        case 3:
          duration.tuplet
            ..enters = 3
            ..times = 2;
        case 5:
          duration.tuplet
            ..enters = 5
            ..times = 4;
        case 6:
          duration.tuplet
            ..enters = 6
            ..times = 4;
        case 7:
          duration.tuplet
            ..enters = 7
            ..times = 4;
        case 9:
          duration.tuplet
            ..enters = 9
            ..times = 8;
        case 10:
          duration.tuplet
            ..enters = 10
            ..times = 8;
        case 11:
          duration.tuplet
            ..enters = 11
            ..times = 8;
        case 12:
          duration.tuplet
            ..enters = 12
            ..times = 8;
        case 13:
          duration.tuplet
            ..enters = 13
            ..times = 8;
      }
    }
    return duration;
  }

  Chord readChord(int stringCount) {
    final chord = Chord(stringCount);
    chord.newFormat = readBool();
    if (!chord.newFormat!) {
      readOldChord(chord);
    } else {
      readNewChord(chord);
    }
    return chord;
  }

  void readOldChord(Chord chord) {
    chord.name = readIntByteSizeString();
    chord.firstFret = readI32();
    if (chord.firstFret != 0) {
      for (var i = 0; i < 6; i++) {
        final fret = readI32();
        if (i < chord.strings.length) chord.strings[i] = fret;
      }
    }
  }

  /// GP3 new-style chord. GP4/GP5 override with their own layout.
  void readNewChord(Chord chord) {
    chord.sharp = readBool();
    final intonation = chord.sharp! ? 'sharp' : 'flat';
    skip(3);
    chord.root = PitchClass(readI32(), intonation: intonation);
    chord.type = ChordType(readI32());
    chord.extension = ChordExtension(readI32());
    chord.bass = PitchClass(readI32(), intonation: intonation);
    chord.tonality = ChordAlteration.fromValue(readI32());
    chord.add = readBool();
    chord.name = readByteSizeString(22);
    chord.fifth = ChordAlteration.fromValue(readI32());
    chord.ninth = ChordAlteration.fromValue(readI32());
    chord.eleventh = ChordAlteration.fromValue(readI32());
    chord.firstFret = readI32();
    for (var i = 0; i < 6; i++) {
      final fret = readI32();
      if (i < chord.strings.length) chord.strings[i] = fret;
    }
    chord.barres = <Barre>[];
    final barresCount = readI32();
    final barreFrets = [for (var i = 0; i < 2; i++) readI32()];
    final barreStarts = [for (var i = 0; i < 2; i++) readI32()];
    final barreEnds = [for (var i = 0; i < 2; i++) readI32()];
    for (var i = 0; i < barresCount && i < 2; i++) {
      chord.barres.add(
        Barre(barreFrets[i], start: barreStarts[i], end: barreEnds[i]),
      );
    }
    chord.omissions = [for (var i = 0; i < 7; i++) readBool()];
    skip(1);
  }

  BeatEffect readBeatEffects(NoteEffect noteEffect) {
    final beatEffects = BeatEffect();
    final flags1 = readU8();
    noteEffect.vibrato = (flags1 & 0x01 != 0) || noteEffect.vibrato;
    beatEffects.vibrato = (flags1 & 0x02 != 0) || beatEffects.vibrato;
    beatEffects.fadeIn = flags1 & 0x10 != 0;
    if (flags1 & 0x20 != 0) {
      final flags2 = readU8();
      beatEffects.slapEffect = SlapEffect.fromValue(flags2);
      if (beatEffects.slapEffect == SlapEffect.none) {
        beatEffects.tremoloBar = readTremoloBar();
      } else {
        readI32();
      }
    }
    if (flags1 & 0x40 != 0) {
      beatEffects.stroke = readBeatStroke();
    }
    if (flags1 & 0x04 != 0) {
      noteEffect.harmonic = const NaturalHarmonic();
    }
    if (flags1 & 0x08 != 0) {
      noteEffect.harmonic = const ArtificialHarmonic();
    }
    return beatEffects;
  }

  BendEffect? readTremoloBar() {
    final barEffect = BendEffect();
    barEffect.type = BendType.dip;
    barEffect.value = readI32();
    barEffect.points = [
      BendPoint(0, 0),
      BendPoint(
        (BendEffect.maxPosition / 2).round(),
        (-barEffect.value / GpByteReader.bendSemitone).round(),
      ),
      BendPoint(BendEffect.maxPosition, 0),
    ];
    return barEffect;
  }

  BeatStroke readBeatStroke() {
    final strokeDown = readI8();
    final strokeUp = readI8();
    if (strokeUp > 0) {
      return BeatStroke(
        direction: BeatStrokeDirection.up,
        value: toStrokeValue(strokeUp),
      );
    } else if (strokeDown > 0) {
      return BeatStroke(
        direction: BeatStrokeDirection.down,
        value: toStrokeValue(strokeDown),
      );
    }
    return BeatStroke();
  }

  int toStrokeValue(int value) {
    switch (value) {
      case 1:
        return Duration.hundredTwentyEighth;
      case 2:
        return Duration.sixtyFourth;
      case 3:
        return Duration.thirtySecond;
      case 4:
        return Duration.sixteenth;
      case 5:
        return Duration.eighth;
      case 6:
        return Duration.quarter;
      default:
        return Duration.sixtyFourth;
    }
  }

  MixTableChange readMixTableChange(Measure measure) =>
      readMixTableChangeCore(measure);

  /// GP3's mix-table-change body (values + durations). Exposed separately so the
  /// GP5 reader can reuse it directly, bypassing GP4's added flag byte — this is
  /// PyGuitarPro's `super(GP4File, self).readMixTableChange(measure)` call.
  MixTableChange readMixTableChangeCore(Measure measure) {
    final tableChange = MixTableChange();
    readMixTableChangeValues(tableChange, measure);
    readMixTableChangeDurations(tableChange);
    return tableChange;
  }

  void readMixTableChangeValues(MixTableChange tableChange, Measure measure) {
    final instrument = readI8();
    final volume = readI8();
    final balance = readI8();
    final chorus = readI8();
    final reverb = readI8();
    final phaser = readI8();
    final tremolo = readI8();
    final tempo = readI32();
    if (instrument >= 0) tableChange.instrument = MixTableItem(instrument);
    if (volume >= 0) tableChange.volume = MixTableItem(volume);
    if (balance >= 0) tableChange.balance = MixTableItem(balance);
    if (chorus >= 0) tableChange.chorus = MixTableItem(chorus);
    if (reverb >= 0) tableChange.reverb = MixTableItem(reverb);
    if (phaser >= 0) tableChange.phaser = MixTableItem(phaser);
    if (tremolo >= 0) tableChange.tremolo = MixTableItem(tremolo);
    if (tempo >= 0) tableChange.tempo = MixTableItem(tempo);
  }

  void readMixTableChangeDurations(MixTableChange tableChange) {
    if (tableChange.volume != null) tableChange.volume!.duration = readI8();
    if (tableChange.balance != null) tableChange.balance!.duration = readI8();
    if (tableChange.chorus != null) tableChange.chorus!.duration = readI8();
    if (tableChange.reverb != null) tableChange.reverb!.duration = readI8();
    if (tableChange.phaser != null) tableChange.phaser!.duration = readI8();
    if (tableChange.tremolo != null) tableChange.tremolo!.duration = readI8();
    if (tableChange.tempo != null) {
      tableChange.tempo!.duration = readI8();
      tableChange.hideTempo = false;
    }
  }

  void readNotes(
    Track track,
    Beat beat,
    Duration duration, [
    NoteEffect? noteEffect,
  ]) {
    final stringFlags = readU8();
    for (final string in track.strings) {
      if (stringFlags & (1 << (7 - string.number)) != 0) {
        final note = Note(beat, effect: (noteEffect ?? NoteEffect()).clone());
        beat.notes.add(note);
        readNote(note, string, track);
      }
      beat.duration = duration;
    }
  }

  Note readNote(Note note, GuitarString guitarString, Track track) {
    final flags = readU8();
    note.string = guitarString.number;
    note.effect.ghostNote = flags & 0x04 != 0;
    note.effect.accentuatedNote = flags & 0x40 != 0;
    if (flags & 0x20 != 0) note.type = NoteType(readU8());
    if (flags & 0x01 != 0) {
      note.duration = readI8();
      note.tuplet = readI8();
    }
    if (flags & 0x10 != 0) {
      note.velocity = unpackVelocity(readI8());
    }
    if (flags & 0x20 != 0) {
      final fret = readI8();
      final value = note.type == NoteType.tie ? getTiedNoteValue(note) : fret;
      note.value = value.clamp(0, 99);
    }
    if (flags & 0x80 != 0) {
      note.effect.leftHandFinger = Fingering(readI8());
      note.effect.rightHandFinger = Fingering(readI8());
    }
    if (flags & 0x08 != 0) {
      note.effect = readNoteEffects(note);
      final harmonic = note.effect.harmonic;
      if (note.effect.isHarmonic && harmonic is TappedHarmonic) {
        note.effect.harmonic = TappedHarmonic(note.value + 12);
      }
    }
    return note;
  }

  int unpackVelocity(int dyn) {
    return Velocities.minVelocity +
        Velocities.velocityIncrement * dyn -
        Velocities.velocityIncrement;
  }

  int getTiedNoteValue(Note note) {
    final measure = note.beat.voice.measure;
    final voiceIndex = measure.voices.indexOf(note.beat.voice);
    final measures = measure.track.measures;
    for (var i = 0; i < measures.length; i++) {
      final m = measures[measures.length - 1 - i];
      final voice = m.voices[voiceIndex];
      final beats = i == 0
          ? voice.beats.sublist(0, voice.beats.indexOf(note.beat))
          : voice.beats;
      for (var j = beats.length - 1; j >= 0; j--) {
        final beat = beats[j];
        if (beat.status != BeatStatus.empty) {
          for (final prevNote in beat.notes) {
            if (prevNote.string == note.string) return prevNote.value;
          }
        }
      }
    }
    return -1;
  }

  NoteEffect readNoteEffects(Note note) {
    final noteEffect = note.effect;
    final flags = readU8();
    noteEffect.hammer = flags & 0x02 != 0;
    noteEffect.letRing = flags & 0x08 != 0;
    if (flags & 0x01 != 0) noteEffect.bend = readBend();
    if (flags & 0x10 != 0) noteEffect.grace = readGrace();
    if (flags & 0x04 != 0) noteEffect.slides = readSlides();
    return noteEffect;
  }

  BendEffect? readBend() {
    final bendEffect = BendEffect();
    bendEffect.type = BendType.fromValue(readI8());
    bendEffect.value = readI32();
    final pointCount = readI32();
    for (var i = 0; i < pointCount; i++) {
      final position =
          (readI32() * BendEffect.maxPosition / GpByteReader.bendPosition)
              .round();
      final value =
          (readI32() * BendEffect.semitoneLength / GpByteReader.bendSemitone)
              .round();
      final vibrato = readBool();
      bendEffect.points.add(BendPoint(position, value, vibrato: vibrato));
    }
    return pointCount > 0 ? bendEffect : null;
  }

  GraceEffect readGrace() {
    final grace = GraceEffect();
    grace.fret = readI8();
    grace.velocity = unpackVelocity(readU8());
    grace.duration = 1 << (7 - readU8());
    grace.isDead = grace.fret == -1;
    grace.isOnBeat = false;
    grace.transition = GraceEffectTransition.fromValue(readI8());
    return grace;
  }

  List<SlideType> readSlides() => <SlideType>[SlideType.shiftSlideTo];
}
