import 'gp4_reader.dart';
import 'models.dart';

/// Ordered direction signs read from a GP5 header block.
class _Directions {
  final List<MapEntry<DirectionSign, int>> signs;
  final List<MapEntry<DirectionSign, int>> fromSigns;
  _Directions(this.signs, this.fromSigns);
}

/// Reader for Guitar Pro 5 files. Extends [GP4File].
class GP5File extends GP4File {
  GP5File(super.data);

  // Version comparison helpers mirroring Python's tuple comparisons.
  int _cmpVersion(List<int> other) {
    final v = versionTuple ?? const <int>[0, 0, 0];
    for (var i = 0; i < 3; i++) {
      final a = i < v.length ? v[i] : 0;
      final b = i < other.length ? other[i] : 0;
      if (a != b) return a < b ? -1 : 1;
    }
    return 0;
  }

  bool get _isAbove500 => _cmpVersion(const [5, 0, 0]) > 0;
  bool get _is500 => _cmpVersion(const [5, 0, 0]) == 0;

  @override
  Song readSong() {
    final song = Song(tracks: <Track>[], measureHeaders: <MeasureHeader>[]);
    song.version = readVersion();
    song.versionTuple = versionTuple;
    if (isClipboard()) song.clipboard = readClipboard();
    readInfo(song);
    song.lyrics = readLyrics();
    song.masterEffect = readRSEMasterEffect();
    song.pageSetup = readPageSetup();
    song.tempoName = readIntByteSizeString();
    song.tempo = readI32();
    song.hideTempo = _isAbove500 ? readBool() : false;
    song.key = KeySignature(readI8(), 0);
    readI32(); // octave
    final channels = readMidiChannels();
    final directions = _readDirections();
    song.masterEffect.reverb = readI32();
    final measureCount = readI32();
    final trackCount = readI32();
    annotateErrors<void>('reading', () {
      _readMeasureHeaders(song, measureCount, directions);
      readTracks(song, trackCount, channels);
      readMeasures(song);
    });
    return song;
  }

  @override
  Clipboard? readClipboard() {
    final clipboard = super.readClipboard();
    if (clipboard == null) return null;
    clipboard.startBeat = readI32();
    clipboard.stopBeat = readI32();
    clipboard.subBarCopy = readI32() != 0;
    return clipboard;
  }

  @override
  void readInfo(Song song) {
    song.title = readIntByteSizeString();
    song.subtitle = readIntByteSizeString();
    song.artist = readIntByteSizeString();
    song.album = readIntByteSizeString();
    song.words = readIntByteSizeString();
    song.music = readIntByteSizeString();
    song.copyright = readIntByteSizeString();
    song.tab = readIntByteSizeString();
    song.instructions = readIntByteSizeString();
    final notesCount = readI32();
    song.notice = <String>[];
    for (var i = 0; i < notesCount; i++) {
      song.notice.add(readIntByteSizeString());
    }
  }

  RSEMasterEffect readRSEMasterEffect() {
    final masterEffect = RSEMasterEffect();
    if (_isAbove500) {
      masterEffect.volume = readI32().toDouble();
      readI32(); // reserved
      masterEffect.equalizer = readEqualizer(11);
    }
    return masterEffect;
  }

  RSEEqualizer readEqualizer(int knobsNumber) {
    final knobs = [
      for (var i = 0; i < knobsNumber; i++) unpackVolumeValue(readI8()),
    ];
    return RSEEqualizer(
      knobs: knobs.sublist(0, knobs.length - 1),
      gain: knobs.last,
    );
  }

  double unpackVolumeValue(int value) => -value / 10;

  PageSetup readPageSetup() {
    final setup = PageSetup();
    setup.pageSize = Point(readI32(), readI32());
    final left = readI32();
    final right = readI32();
    final top = readI32();
    final bottom = readI32();
    setup.pageMargin = Padding(right, top, left, bottom);
    setup.scoreSizeProportion = readI32() / 100;
    setup.headerAndFooter = readI16();
    setup.title = readIntByteSizeString();
    setup.subtitle = readIntByteSizeString();
    setup.artist = readIntByteSizeString();
    setup.album = readIntByteSizeString();
    setup.words = readIntByteSizeString();
    setup.music = readIntByteSizeString();
    setup.wordsAndMusic = readIntByteSizeString();
    setup.copyright = '${readIntByteSizeString()}\n${readIntByteSizeString()}';
    setup.pageNumber = readIntByteSizeString();
    return setup;
  }

  _Directions _readDirections() {
    final signLabels = ['Coda', 'Double Coda', 'Segno', 'Segno Segno', 'Fine'];
    final fromLabels = [
      'Da Capo',
      'Da Capo al Coda',
      'Da Capo al Double Coda',
      'Da Capo al Fine',
      'Da Segno',
      'Da Segno al Coda',
      'Da Segno al Double Coda',
      'Da Segno al Fine',
      'Da Segno Segno',
      'Da Segno Segno al Coda',
      'Da Segno Segno al Double Coda',
      'Da Segno Segno al Fine',
      'Da Coda',
      'Da Double Coda',
    ];
    final signs = [
      for (final label in signLabels) MapEntry(DirectionSign(label), readI16()),
    ];
    final fromSigns = [
      for (final label in fromLabels) MapEntry(DirectionSign(label), readI16()),
    ];
    return _Directions(signs, fromSigns);
  }

  void _readMeasureHeaders(
    Song song,
    int measureCount,
    _Directions directions,
  ) {
    super.readMeasureHeaders(song, measureCount);
    for (final entry in directions.signs) {
      if (entry.value > -1) {
        song.measureHeaders[entry.value - 1].direction = entry.key;
      }
    }
    for (final entry in directions.fromSigns) {
      if (entry.value > -1) {
        song.measureHeaders[entry.value - 1].fromDirection = entry.key;
      }
    }
  }

  @override
  MeasureHeader readMeasureHeader(
    int number,
    Song song, [
    MeasureHeader? previous,
  ]) {
    if (previous != null) skip(1); // always 0
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
    if (flags & 0x20 != 0) header.marker = readMarker(header);
    if (flags & 0x40 != 0) {
      final root = readI8();
      final type = readI8();
      header.keySignature = KeySignature(root, type);
    } else if (header.number > 1) {
      header.keySignature = previous!.keySignature;
    }
    if (flags & 0x10 != 0) {
      header.repeatAlternative = readRepeatAlternative(song.measureHeaders);
    }
    header.hasDoubleBar = flags & 0x80 != 0;
    if (header.repeatClose > -1) header.repeatClose -= 1;
    if (flags & 0x03 != 0) {
      header.timeSignature.beams = [for (var i = 0; i < 4; i++) readU8()];
    } else {
      header.timeSignature.beams = previous!.timeSignature.beams;
    }
    if (flags & 0x10 == 0) skip(1); // always 0
    header.tripletFeel = TripletFeel.fromValue(readU8());
    return header;
  }

  @override
  int readRepeatAlternative(List<MeasureHeader> measureHeaders) => readU8();

  @override
  void readTracks(Song song, int trackCount, List<MidiChannel> channels) {
    super.readTracks(song, trackCount, channels);
    skip(_is500 ? 2 : 1); // always 0
  }

  @override
  void readTrack(Track track, List<MidiChannel> channels) {
    if (track.number == 1 || _is500) skip(1); // always 0
    final flags1 = readU8();
    track.isPercussionTrack = flags1 & 0x01 != 0;
    track.is12StringedGuitarTrack = flags1 & 0x02 != 0;
    track.isBanjoTrack = flags1 & 0x04 != 0;
    track.isVisible = flags1 & 0x08 != 0;
    track.isSolo = flags1 & 0x10 != 0;
    track.isMute = flags1 & 0x20 != 0;
    track.useRSE = flags1 & 0x40 != 0;
    track.indicateTuning = flags1 & 0x80 != 0;
    track.name = readByteSizeString(40);
    final stringCount = readI32();
    for (var i = 0; i < 7; i++) {
      final iTuning = readI32();
      if (stringCount > i) track.strings.add(GuitarString(i + 1, iTuning));
    }
    track.port = readI32();
    track.channel = readChannel(channels);
    if (track.channel.channel == 9) track.isPercussionTrack = true;
    track.fretCount = readI32();
    track.offset = readI32();
    track.color = readColor();

    final flags2 = readI16();
    track.settings = TrackSettings();
    track.settings.tablature = flags2 & 0x0001 != 0;
    track.settings.notation = flags2 & 0x0002 != 0;
    track.settings.diagramsAreBelow = flags2 & 0x0004 != 0;
    track.settings.showRhythm = flags2 & 0x0008 != 0;
    track.settings.forceHorizontal = flags2 & 0x0010 != 0;
    track.settings.forceChannels = flags2 & 0x0020 != 0;
    track.settings.diagramList = flags2 & 0x0040 != 0;
    track.settings.diagramsInScore = flags2 & 0x0080 != 0;
    track.settings.autoLetRing = flags2 & 0x0200 != 0;
    track.settings.autoBrush = flags2 & 0x0400 != 0;
    track.settings.extendRhythmic = flags2 & 0x0800 != 0;

    track.rse = TrackRSE();
    track.rse.autoAccentuation = Accentuation.fromValue(readU8());
    track.channel.bank = readU8();
    track.rse.humanize = readU8();
    track.clefTranspose = readI32();
    track.clefTransposeSecondary = readI32();
    readI32(); // typically -1 or 100
    skip(12);
    track.rse.instrument = readRSEInstrument();
    if (_isAbove500) {
      track.rse.equalizer = readEqualizer(4);
      readRSEInstrumentEffect(track.rse.instrument);
    }
  }

  RSEInstrument readRSEInstrument() {
    final instrument = RSEInstrument();
    instrument.instrument = readI32();
    instrument.unknown = readI32();
    instrument.soundBank = readI32();
    if (_is500) {
      instrument.effectNumber = readI16();
      skip(1);
    } else {
      instrument.effectNumber = readI32();
    }
    return instrument;
  }

  RSEInstrument readRSEInstrumentEffect(RSEInstrument? rseInstrument) {
    if (_isAbove500) {
      final effect = readIntByteSizeString();
      final effectCategory = readIntByteSizeString();
      if (rseInstrument != null) {
        rseInstrument.effect = effect;
        rseInstrument.effectCategory = effectCategory;
      }
    }
    return rseInstrument ?? RSEInstrument();
  }

  @override
  void readMeasure(Measure measure) {
    final start = measure.start;
    final voiceCount = measure.voices.length < Measure.maxVoices
        ? measure.voices.length
        : Measure.maxVoices;
    for (var number = 0; number < voiceCount; number++) {
      currentVoiceNumber = number + 1;
      readVoice(start, measure.voices[number]);
    }
    currentVoiceNumber = null;
    measure.lineBreak = LineBreak.fromValue(readU8(defaultValue: 0));
  }

  @override
  num readBeat(num start, Voice voice) {
    final duration = super.readBeat(start, voice);
    final beat = getBeat(voice, start);
    final flags2 = readI16();
    if (flags2 & 0x0010 != 0) beat.octave = Octave.ottava;
    if (flags2 & 0x0020 != 0) beat.octave = Octave.ottavaBassa;
    if (flags2 & 0x0040 != 0) beat.octave = Octave.quindicesima;
    if (flags2 & 0x0100 != 0) beat.octave = Octave.quindicesimaBassa;
    final display = BeatDisplay();
    display.breakBeam = flags2 & 0x0001 != 0;
    display.forceBeam = flags2 & 0x0004 != 0;
    display.forceBracket = flags2 & 0x2000 != 0;
    display.breakSecondaryTuplet = flags2 & 0x1000 != 0;
    if (flags2 & 0x0002 != 0) display.beamDirection = VoiceDirection.down;
    if (flags2 & 0x0008 != 0) display.beamDirection = VoiceDirection.up;
    if (flags2 & 0x0200 != 0) display.tupletBracket = TupletBracket.start;
    if (flags2 & 0x0400 != 0) display.tupletBracket = TupletBracket.end;
    if (flags2 & 0x0800 != 0) display.breakSecondary = readU8();
    beat.display = display;
    return duration;
  }

  @override
  BeatStroke readBeatStroke() => super.readBeatStroke().swapDirection();

  @override
  MixTableChange readMixTableChange(Measure measure) {
    final tableChange = readMixTableChangeCore(measure);
    final flags = readMixTableChangeFlags(tableChange);
    tableChange.wah = readWahEffect(flags);
    readRSEInstrumentEffect(tableChange.rse);
    return tableChange;
  }

  @override
  void readMixTableChangeValues(MixTableChange tableChange, Measure measure) {
    final instrument = readI8();
    final rse = readRSEInstrument();
    if (_is500) skip(1);
    final volume = readI8();
    final balance = readI8();
    final chorus = readI8();
    final reverb = readI8();
    final phaser = readI8();
    final tremolo = readI8();
    final tempoName = readIntByteSizeString();
    final tempo = readI32();
    if (instrument >= 0) {
      tableChange.instrument = MixTableItem(instrument);
      tableChange.rse = rse;
    }
    if (volume >= 0) tableChange.volume = MixTableItem(volume);
    if (balance >= 0) tableChange.balance = MixTableItem(balance);
    if (chorus >= 0) tableChange.chorus = MixTableItem(chorus);
    if (reverb >= 0) tableChange.reverb = MixTableItem(reverb);
    if (phaser >= 0) tableChange.phaser = MixTableItem(phaser);
    if (tremolo >= 0) tableChange.tremolo = MixTableItem(tremolo);
    if (tempo >= 0) {
      tableChange.tempo = MixTableItem(tempo);
      tableChange.tempoName = tempoName;
    }
  }

  @override
  void readMixTableChangeDurations(MixTableChange tableChange) {
    if (tableChange.volume != null) tableChange.volume!.duration = readI8();
    if (tableChange.balance != null) tableChange.balance!.duration = readI8();
    if (tableChange.chorus != null) tableChange.chorus!.duration = readI8();
    if (tableChange.reverb != null) tableChange.reverb!.duration = readI8();
    if (tableChange.phaser != null) tableChange.phaser!.duration = readI8();
    if (tableChange.tremolo != null) tableChange.tremolo!.duration = readI8();
    if (tableChange.tempo != null) {
      tableChange.tempo!.duration = readI8();
      tableChange.hideTempo = _isAbove500 && readBool();
    }
  }

  @override
  int readMixTableChangeFlags(MixTableChange tableChange) {
    final flags = super.readMixTableChangeFlags(tableChange);
    tableChange.useRSE = flags & 0x40 != 0;
    return flags;
  }

  WahEffect readWahEffect(int flags) =>
      WahEffect(value: readI8(), display: flags & 0x80 != 0);

  @override
  Note readNote(Note note, GuitarString guitarString, Track track) {
    final flags = readU8();
    note.string = guitarString.number;
    note.effect.heavyAccentuatedNote = flags & 0x02 != 0;
    note.effect.ghostNote = flags & 0x04 != 0;
    note.effect.accentuatedNote = flags & 0x40 != 0;
    if (flags & 0x20 != 0) note.type = NoteType(readU8());
    if (flags & 0x10 != 0) note.velocity = unpackVelocity(readI8());
    if (flags & 0x20 != 0) {
      final fret = readI8();
      final value = note.type == NoteType.tie ? getTiedNoteValue(note) : fret;
      note.value = (value >= 0 && value < 100) ? value : 0;
    }
    if (flags & 0x80 != 0) {
      note.effect.leftHandFinger = Fingering(readI8());
      note.effect.rightHandFinger = Fingering(readI8());
    }
    if (flags & 0x01 != 0) note.durationPercent = readF64();
    final flags2 = readU8();
    note.swapAccidentals = flags2 & 0x02 != 0;
    if (flags & 0x08 != 0) note.effect = readNoteEffects(note);
    return note;
  }

  @override
  GraceEffect readGrace() {
    final grace = GraceEffect();
    grace.fret = readU8();
    grace.velocity = unpackVelocity(readU8());
    grace.transition = GraceEffectTransition.fromValue(readU8());
    grace.duration = 1 << (7 - readU8());
    final flags = readU8();
    grace.isDead = flags & 0x01 != 0;
    grace.isOnBeat = flags & 0x02 != 0;
    return grace;
  }

  @override
  List<SlideType> readSlides() {
    final slideType = readU8();
    final slides = <SlideType>[];
    if (slideType & 0x01 != 0) slides.add(SlideType.shiftSlideTo);
    if (slideType & 0x02 != 0) slides.add(SlideType.legatoSlideTo);
    if (slideType & 0x04 != 0) slides.add(SlideType.outDownwards);
    if (slideType & 0x08 != 0) slides.add(SlideType.outUpwards);
    if (slideType & 0x10 != 0) slides.add(SlideType.intoFromBelow);
    if (slideType & 0x20 != 0) slides.add(SlideType.intoFromAbove);
    return slides;
  }

  @override
  HarmonicEffect readHarmonic(Note note) {
    final harmonicType = readI8();
    switch (harmonicType) {
      case 1:
        return const NaturalHarmonic();
      case 2:
        final semitone = readU8();
        final accidental = readI8();
        final pitchClass = PitchClass(semitone, accidental: accidental);
        final octave = Octave.fromValue(readU8());
        return ArtificialHarmonic(pitchClass, octave);
      case 3:
        return TappedHarmonic(readU8());
      case 4:
        return const PinchHarmonic();
      case 5:
        return const SemiHarmonic();
      default:
        throw GpException('unknown harmonic type $harmonicType');
    }
  }
}
