/// Data model for the Guitar Pro song tree, ported from PyGuitarPro's
/// `models.py`. The classes are plain mutable holders — the readers build them
/// up field by field, exactly as PyGuitarPro does.
///
/// Compared to PyGuitarPro this port drops the write-side helpers (`isDefault`,
/// equality/hashing machinery) and keeps only what the readers need, plus the
/// computed properties consulted *while reading* (durations, measure lengths,
/// real note values, percussion detection).
library;

/// Raised for malformed files or unsupported versions.
class GpException implements Exception {
  final String message;
  const GpException(this.message);
  @override
  String toString() => 'GpException: $message';
}

// ===========================================================================
// Lenient enums
//
// PyGuitarPro uses a `LenientEnum` for a few enums whose on-disk value may fall
// outside the known set; instead of raising, it keeps the raw value under an
// "unknown" member. We model those as small value classes.
// ===========================================================================

/// Note is normal, tied to a previous one, dead/muted, or a rest.
class NoteType {
  final int value;
  const NoteType(this.value);

  static const NoteType rest = NoteType(0);
  static const NoteType normal = NoteType(1);
  static const NoteType tie = NoteType(2);
  static const NoteType dead = NoteType(3);

  @override
  bool operator ==(Object other) => other is NoteType && other.value == value;
  @override
  int get hashCode => value.hashCode;
  @override
  String toString() => 'NoteType($value)';
}

/// Type of a chord (major, minor, …). Lenient: unknown values are preserved.
class ChordType {
  final int value;
  const ChordType(this.value);

  static const ChordType major = ChordType(0);
  static const ChordType seventh = ChordType(1);
  static const ChordType majorSeventh = ChordType(2);
  static const ChordType sixth = ChordType(3);
  static const ChordType minor = ChordType(4);
  static const ChordType minorSeventh = ChordType(5);
  static const ChordType minorMajor = ChordType(6);
  static const ChordType minorSixth = ChordType(7);
  static const ChordType suspendedSecond = ChordType(8);
  static const ChordType suspendedFourth = ChordType(9);
  static const ChordType seventhSuspendedSecond = ChordType(10);
  static const ChordType seventhSuspendedFourth = ChordType(11);
  static const ChordType diminished = ChordType(12);
  static const ChordType augmented = ChordType(13);
  static const ChordType power = ChordType(14);

  @override
  bool operator ==(Object other) => other is ChordType && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Chord extension (ninth, eleventh, thirteenth). Lenient.
class ChordExtension {
  final int value;
  const ChordExtension(this.value);

  static const ChordExtension none = ChordExtension(0);
  static const ChordExtension ninth = ChordExtension(1);
  static const ChordExtension eleventh = ChordExtension(2);
  static const ChordExtension thirteenth = ChordExtension(3);

  @override
  bool operator ==(Object other) =>
      other is ChordExtension && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Left/right-hand fingering. Lenient.
class Fingering {
  final int value;
  const Fingering(this.value);

  static const Fingering open = Fingering(-1);
  static const Fingering thumb = Fingering(0);
  static const Fingering index = Fingering(1);
  static const Fingering middle = Fingering(2);
  static const Fingering annular = Fingering(3);
  static const Fingering little = Fingering(4);

  @override
  bool operator ==(Object other) => other is Fingering && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

// ===========================================================================
// Strict enums
// ===========================================================================

enum TripletFeel {
  none(0),
  eighth(1),
  sixteenth(2);

  final int value;
  const TripletFeel(this.value);
  static TripletFeel fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown TripletFeel $v'),
  );
}

enum LineBreak {
  none(0),
  breakLine(1),
  protect(2);

  final int value;
  const LineBreak(this.value);
  static LineBreak fromValue(int v) =>
      values.firstWhere((e) => e.value == v, orElse: () => LineBreak.none);
}

enum VoiceDirection {
  none(0),
  up(1),
  down(2);

  final int value;
  const VoiceDirection(this.value);
}

enum BeatStrokeDirection {
  none(0),
  up(1),
  down(2);

  final int value;
  const BeatStrokeDirection(this.value);
  static BeatStrokeDirection fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown BeatStrokeDirection $v'),
  );
}

enum SlapEffect {
  none(0),
  tapping(1),
  slapping(2),
  popping(3);

  final int value;
  const SlapEffect(this.value);
  static SlapEffect fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown SlapEffect $v'),
  );
}

enum TupletBracket {
  none(0),
  start(1),
  end(2);

  final int value;
  const TupletBracket(this.value);
}

enum Octave {
  none(0),
  ottava(1),
  quindicesima(2),
  ottavaBassa(3),
  quindicesimaBassa(4);

  final int value;
  const Octave(this.value);
  static Octave fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown Octave $v'),
  );
}

enum BeatStatus {
  empty(0),
  normal(1),
  rest(2);

  final int value;
  const BeatStatus(this.value);
  static BeatStatus fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown BeatStatus $v'),
  );
}

enum GraceEffectTransition {
  none(0),
  slide(1),
  bend(2),
  hammer(3);

  final int value;
  const GraceEffectTransition(this.value);
  static GraceEffectTransition fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown GraceEffectTransition $v'),
  );
}

enum SlideType {
  intoFromAbove(-2),
  intoFromBelow(-1),
  none(0),
  shiftSlideTo(1),
  legatoSlideTo(2),
  outDownwards(3),
  outUpwards(4);

  final int value;
  const SlideType(this.value);
  static SlideType fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown SlideType $v'),
  );
}

enum ChordAlteration {
  perfect(0),
  diminished(1),
  augmented(2);

  final int value;
  const ChordAlteration(this.value);
  static ChordAlteration fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown ChordAlteration $v'),
  );
}

enum Accentuation {
  none(0),
  verySoft(1),
  soft(2),
  medium(3),
  strong(4),
  veryStrong(5);

  final int value;
  const Accentuation(this.value);
  static Accentuation fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown Accentuation $v'),
  );
}

enum BendType {
  none(0),
  bend(1),
  bendRelease(2),
  bendReleaseBend(3),
  prebend(4),
  prebendRelease(5),
  dip(6),
  dive(7),
  releaseUp(8),
  invertedDip(9),
  returnBar(10),
  releaseDown(11);

  final int value;
  const BendType(this.value);
  static BendType fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown BendType $v'),
  );
}

// ===========================================================================
// Velocities / dynamics
// ===========================================================================

/// MIDI velocity presets, matching PyGuitarPro's `Velocities`.
class Velocities {
  static const int minVelocity = 15;
  static const int velocityIncrement = 16;
  static const int pianoPianissimo = minVelocity;
  static const int forte = minVelocity + velocityIncrement * 5;
  static const int defaultVelocity = forte;
}

// ===========================================================================
// Simple value objects
// ===========================================================================

/// An RGB color (the 4th, blank, byte is dropped on read).
class Color {
  final int r;
  final int g;
  final int b;
  const Color(this.r, this.g, this.b);

  static const Color black = Color(0, 0, 0);
  static const Color red = Color(255, 0, 0);
}

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
}

class Padding {
  final int right;
  final int top;
  final int left;
  final int bottom;
  const Padding(this.right, this.top, this.left, this.bottom);
}

/// Key signature, identified by (root, type) where type 0 = major, 1 = minor.
class KeySignature {
  final int root;
  final int type;
  const KeySignature(this.root, this.type);

  @override
  bool operator ==(Object other) =>
      other is KeySignature && other.root == root && other.type == type;
  @override
  int get hashCode => Object.hash(root, type);
}

/// A navigation sign (Coda, Segno, …).
class DirectionSign {
  final String name;
  const DirectionSign(this.name);

  @override
  bool operator ==(Object other) =>
      other is DirectionSign && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// A pitch class. Only the integer constructors used by the readers are ported
/// (note-name parsing from PyGuitarPro is omitted).
class PitchClass {
  late int just;
  late int accidental;
  late int value;
  late String intonation;

  PitchClass(int just, {int? accidental, String? intonation}) {
    int pitch;
    if (accidental == null) {
      final v = just % 12;
      // Pick a spelling so we can derive the accidental, mirroring the source.
      const sharp = [
        'C',
        'C#',
        'D',
        'D#',
        'E',
        'F',
        'F#',
        'G',
        'G#',
        'A',
        'A#',
        'B',
      ];
      final name = sharp[v];
      final acc = name.endsWith('#') ? 1 : 0;
      pitch = v - acc;
      this.accidental = acc;
    } else {
      pitch = just;
      this.accidental = accidental;
    }
    this.just = pitch % 12;
    value = this.just + this.accidental;
    this.intonation = intonation ?? (this.accidental == -1 ? 'flat' : 'sharp');
  }
}

// ===========================================================================
// Tuplet / Duration / TimeSignature
// ===========================================================================

/// An *n:m* tuplet. [enters] notes are played in the time of [times].
class Tuplet {
  int enters;
  int times;
  Tuplet({this.enters = 1, this.times = 1});

  /// Converts a straight tick [time] into tuplet time, staying an [int] when the
  /// division is exact and falling back to [double] otherwise.
  num convertTime(int time) {
    final numerator = time * times;
    return numerator % enters == 0 ? numerator ~/ enters : numerator / enters;
  }
}

/// A note/beat duration. Tick values are derived from [quarterTime].
class Duration {
  static const int quarterTime = 960;

  static const int whole = 1;
  static const int half = 2;
  static const int quarter = 4;
  static const int eighth = 8;
  static const int sixteenth = 16;
  static const int thirtySecond = 32;
  static const int sixtyFourth = 64;
  static const int hundredTwentyEighth = 128;

  int value;
  bool isDotted;
  Tuplet tuplet;

  Duration({this.value = quarter, this.isDotted = false, Tuplet? tuplet})
    : tuplet = tuplet ?? Tuplet();

  /// Duration in ticks (see [quarterTime]).
  num get time {
    var result = quarterTime * 4 ~/ value;
    if (isDotted) result += result ~/ 2;
    return tuplet.convertTime(result);
  }
}

/// A time signature. [denominator] is stored as a [Duration].
class TimeSignature {
  int numerator;
  Duration denominator;
  List<int> beams;

  TimeSignature({this.numerator = 4, Duration? denominator, List<int>? beams})
    : denominator = denominator ?? Duration(),
      beams = beams ?? <int>[2, 2, 2, 2];
}

// ===========================================================================
// Headers / markers
// ===========================================================================

class Marker {
  String title;
  Color color;
  Marker({this.title = 'Section', this.color = Color.red});
}

/// Per-measure metadata shared across tracks.
class MeasureHeader {
  int number;
  num start;
  bool hasDoubleBar;
  KeySignature keySignature;
  TimeSignature timeSignature;
  Marker? marker;
  bool isRepeatOpen;
  int repeatAlternative;
  int repeatClose;
  TripletFeel tripletFeel;
  DirectionSign? direction;
  DirectionSign? fromDirection;

  MeasureHeader({
    this.number = 1,
    this.start = Duration.quarterTime,
    this.hasDoubleBar = false,
    KeySignature? keySignature,
    TimeSignature? timeSignature,
    this.marker,
    this.isRepeatOpen = false,
    this.repeatAlternative = 0,
    this.repeatClose = -1,
    this.tripletFeel = TripletFeel.none,
    this.direction,
    this.fromDirection,
  }) : keySignature = keySignature ?? const KeySignature(0, 0),
       timeSignature = timeSignature ?? TimeSignature();

  num get length => timeSignature.numerator * timeSignature.denominator.time;
  num get end => start + length;
}

// ===========================================================================
// Lyrics / page setup / MIDI
// ===========================================================================

class LyricLine {
  int startingMeasure;
  String lyrics;
  LyricLine({this.startingMeasure = 1, this.lyrics = ''});
}

class Lyrics {
  static const int maxLineCount = 5;
  int trackChoice;
  List<LyricLine> lines;
  Lyrics({this.trackChoice = 0, List<LyricLine>? lines})
    : lines =
          lines ?? List<LyricLine>.generate(maxLineCount, (_) => LyricLine());
}

class PageSetup {
  Point pageSize = const Point(210, 297);
  Padding pageMargin = const Padding(10, 15, 10, 10);
  double scoreSizeProportion = 1.0;
  int headerAndFooter = 0;
  String title = '%title%';
  String subtitle = '%subtitle%';
  String artist = '%artist%';
  String album = '%album%';
  String words = 'Words by %words%';
  String music = 'Music by %music%';
  String wordsAndMusic = 'Words & Music by %WORDSMUSIC%';
  String copyright = '';
  String pageNumber = 'Page %N%/%P%';
}

/// A MIDI channel describing playback for a track.
class MidiChannel {
  static const int defaultPercussionChannel = 9;

  int channel;
  int effectChannel;
  int instrument;
  int volume;
  int balance;
  int chorus;
  int reverb;
  int phaser;
  int tremolo;
  int bank;

  MidiChannel({
    this.channel = 0,
    this.effectChannel = 1,
    this.instrument = 25,
    this.volume = 104,
    this.balance = 64,
    this.chorus = 0,
    this.reverb = 0,
    this.phaser = 0,
    this.tremolo = 0,
    this.bank = 0,
  });

  bool get isPercussionChannel => channel % 16 == defaultPercussionChannel;
}

// ===========================================================================
// RSE (Realistic Sound Engine) structures
// ===========================================================================

class RSEEqualizer {
  List<double> knobs;
  double gain;
  RSEEqualizer({List<double>? knobs, this.gain = 0.0})
    : knobs = knobs ?? <double>[];
}

class RSEMasterEffect {
  double volume;
  int reverb;
  RSEEqualizer equalizer;
  RSEMasterEffect({this.volume = 0, this.reverb = 0, RSEEqualizer? equalizer})
    : equalizer = equalizer ?? RSEEqualizer(knobs: List.filled(10, 0.0));
}

class RSEInstrument {
  int instrument;
  int unknown;
  int soundBank;
  int effectNumber;
  String effectCategory;
  String effect;
  RSEInstrument({
    this.instrument = -1,
    this.unknown = -1,
    this.soundBank = -1,
    this.effectNumber = -1,
    this.effectCategory = '',
    this.effect = '',
  });
}

class TrackRSE {
  RSEInstrument instrument;
  RSEEqualizer equalizer;
  int humanize;
  Accentuation autoAccentuation;
  TrackRSE({
    RSEInstrument? instrument,
    RSEEqualizer? equalizer,
    this.humanize = 0,
    this.autoAccentuation = Accentuation.none,
  }) : instrument = instrument ?? RSEInstrument(),
       equalizer = equalizer ?? RSEEqualizer(knobs: List.filled(3, 0.0));
}

class TrackSettings {
  bool tablature = true;
  bool notation = true;
  bool diagramsAreBelow = false;
  bool showRhythm = false;
  bool forceHorizontal = false;
  bool forceChannels = false;
  bool diagramList = true;
  bool diagramsInScore = false;
  bool autoLetRing = false;
  bool autoBrush = false;
  bool extendRhythmic = false;
}

// ===========================================================================
// Song / Track / Measure / Voice / Beat / Note
// ===========================================================================

/// Top-level node of the song model.
class Song {
  String? version;
  List<int>? versionTuple;
  Clipboard? clipboard;
  String title = '';
  String subtitle = '';
  String artist = '';
  String album = '';
  String words = '';
  String music = '';
  String copyright = '';
  String tab = '';
  String instructions = '';
  List<String> notice = <String>[];
  Lyrics lyrics = Lyrics();
  PageSetup pageSetup = PageSetup();
  String tempoName = 'Moderate';
  int tempo = 120;
  bool hideTempo = false;
  KeySignature key = const KeySignature(0, 0);
  List<MeasureHeader> measureHeaders;
  List<Track> tracks;
  RSEMasterEffect masterEffect = RSEMasterEffect();

  Song({List<MeasureHeader>? measureHeaders, List<Track>? tracks})
    : measureHeaders = measureHeaders ?? <MeasureHeader>[],
      tracks = tracks ?? <Track>[];

  void addMeasureHeader(MeasureHeader header) {
    measureHeaders.add(header);
  }
}

class Clipboard {
  int startMeasure = 1;
  int stopMeasure = 1;
  int startTrack = 1;
  int stopTrack = 1;
  int startBeat = 1;
  int stopBeat = 1;
  bool subBarCopy = false;
}

/// A guitar string with its open-note MIDI value.
class GuitarString {
  final int number;
  final int value;
  const GuitarString(this.number, this.value);
}

/// A track: a sequence of measures on a tuned instrument.
class Track {
  final Song song;
  int number;
  int fretCount;
  int offset;
  bool isPercussionTrack;
  bool is12StringedGuitarTrack;
  bool isBanjoTrack;
  bool isVisible;
  bool isSolo;
  bool isMute;
  bool indicateTuning;
  String name;
  List<Measure> measures;
  List<GuitarString> strings;
  int port;
  MidiChannel channel;
  Color color;
  TrackSettings settings;
  bool useRSE;
  TrackRSE rse;
  int? clefTranspose;
  int? clefTransposeSecondary;

  Track(
    this.song, {
    this.number = 1,
    this.fretCount = 24,
    this.offset = 0,
    this.isPercussionTrack = false,
    this.is12StringedGuitarTrack = false,
    this.isBanjoTrack = false,
    this.isVisible = true,
    this.isSolo = false,
    this.isMute = false,
    this.indicateTuning = false,
    this.name = 'Track 1',
    List<Measure>? measures,
    List<GuitarString>? strings,
    this.port = 1,
    MidiChannel? channel,
    this.color = Color.red,
    TrackSettings? settings,
    this.useRSE = false,
    TrackRSE? rse,
    this.clefTranspose,
    this.clefTransposeSecondary,
  }) : measures = measures ?? <Measure>[],
       strings = strings ?? <GuitarString>[],
       channel = channel ?? MidiChannel(),
       settings = settings ?? TrackSettings(),
       rse = rse ?? TrackRSE();
}

/// A measure: holds [maxVoices] voices of beats. Several header properties are
/// promoted here for convenience, matching PyGuitarPro.
class Measure {
  static const int maxVoices = 2;

  final Track track;
  final MeasureHeader header;
  List<Voice> voices;
  LineBreak lineBreak;

  Measure(
    this.track,
    this.header, {
    List<Voice>? voices,
    this.lineBreak = LineBreak.none,
  }) : voices = voices ?? <Voice>[] {
    if (this.voices.isEmpty) {
      for (var i = 0; i < maxVoices; i++) {
        this.voices.add(Voice(this));
      }
    }
  }

  int get number => header.number;
  num get start => header.start;
  num get end => header.end;
  num get length => header.length;
  TimeSignature get timeSignature => header.timeSignature;
}

/// A voice: an ordered list of beats within a measure.
class Voice {
  final Measure measure;
  List<Beat> beats;
  VoiceDirection direction;
  Voice(this.measure, {List<Beat>? beats, this.direction = VoiceDirection.none})
    : beats = beats ?? <Beat>[];
}

class BeatStroke {
  BeatStrokeDirection direction;
  int value;
  BeatStroke({this.direction = BeatStrokeDirection.none, this.value = 0});

  /// Returns a copy with up/down swapped (GP5 stores strokes the other way).
  BeatStroke swapDirection() {
    if (direction == BeatStrokeDirection.up) {
      return BeatStroke(direction: BeatStrokeDirection.down, value: value);
    }
    if (direction == BeatStrokeDirection.down) {
      return BeatStroke(direction: BeatStrokeDirection.up, value: value);
    }
    return this;
  }
}

class BeatEffect {
  BeatStroke stroke;
  bool hasRasgueado;
  BeatStrokeDirection pickStroke;
  Chord? chord;
  bool fadeIn;
  BendEffect? tremoloBar;
  MixTableChange? mixTableChange;
  SlapEffect slapEffect;
  bool vibrato;

  BeatEffect({
    BeatStroke? stroke,
    this.hasRasgueado = false,
    this.pickStroke = BeatStrokeDirection.none,
    this.chord,
    this.fadeIn = false,
    this.tremoloBar,
    this.mixTableChange,
    this.slapEffect = SlapEffect.none,
    this.vibrato = false,
  }) : stroke = stroke ?? BeatStroke();

  bool get isChord => chord != null;
}

class BeatDisplay {
  bool breakBeam = false;
  bool forceBeam = false;
  VoiceDirection beamDirection = VoiceDirection.none;
  TupletBracket tupletBracket = TupletBracket.none;
  int breakSecondary = 0;
  bool breakSecondaryTuplet = false;
  bool forceBracket = false;
}

/// A beat: a chord/strum of notes sharing a duration.
class Beat {
  final Voice voice;
  List<Note> notes;
  Duration duration;
  String? text;
  num? start;
  BeatEffect effect;
  Octave octave;
  BeatDisplay display;
  BeatStatus status;

  Beat(
    this.voice, {
    List<Note>? notes,
    Duration? duration,
    this.text,
    this.start,
    BeatEffect? effect,
    this.octave = Octave.none,
    BeatDisplay? display,
    this.status = BeatStatus.empty,
  }) : notes = notes ?? <Note>[],
       duration = duration ?? Duration(),
       effect = effect ?? BeatEffect(),
       display = display ?? BeatDisplay();
}

// ---- Note effects -------------------------------------------------------

class BendPoint {
  int position;
  int value;
  bool vibrato;
  BendPoint(this.position, this.value, {this.vibrato = false});
}

class BendEffect {
  static const int semitoneLength = 1;
  static const int maxPosition = 12;
  static const int maxValue = semitoneLength * 12;

  BendType type;
  int value;
  List<BendPoint> points;
  BendEffect({
    this.type = BendType.none,
    this.value = 0,
    List<BendPoint>? points,
  }) : points = points ?? <BendPoint>[];
}

class GraceEffect {
  int duration;
  int fret;
  bool isDead;
  bool isOnBeat;
  GraceEffectTransition transition;
  int velocity;
  GraceEffect({
    this.duration = 32,
    this.fret = 0,
    this.isDead = false,
    this.isOnBeat = false,
    this.transition = GraceEffectTransition.none,
    this.velocity = Velocities.defaultVelocity,
  });
}

class TrillEffect {
  int fret;
  Duration duration;
  TrillEffect({this.fret = 0, Duration? duration})
    : duration = duration ?? Duration();
}

class TremoloPickingEffect {
  Duration duration;
  TremoloPickingEffect({Duration? duration})
    : duration = duration ?? Duration();
}

/// Harmonic effect base — [type] mirrors PyGuitarPro's numeric tag.
class HarmonicEffect {
  final int type;
  const HarmonicEffect(this.type);
}

class NaturalHarmonic extends HarmonicEffect {
  const NaturalHarmonic() : super(1);
}

class ArtificialHarmonic extends HarmonicEffect {
  final PitchClass? pitch;
  final Octave? octave;
  const ArtificialHarmonic([this.pitch, this.octave]) : super(2);
}

class TappedHarmonic extends HarmonicEffect {
  final int? fret;
  const TappedHarmonic([this.fret]) : super(3);
}

class PinchHarmonic extends HarmonicEffect {
  const PinchHarmonic() : super(4);
}

class SemiHarmonic extends HarmonicEffect {
  const SemiHarmonic() : super(5);
}

/// All effects applicable to a single note.
class NoteEffect {
  bool accentuatedNote;
  BendEffect? bend;
  bool ghostNote;
  GraceEffect? grace;
  bool hammer;
  HarmonicEffect? harmonic;
  bool heavyAccentuatedNote;
  Fingering leftHandFinger;
  bool letRing;
  bool palmMute;
  Fingering rightHandFinger;
  List<SlideType> slides;
  bool staccato;
  TremoloPickingEffect? tremoloPicking;
  TrillEffect? trill;
  bool vibrato;

  NoteEffect({
    this.accentuatedNote = false,
    this.bend,
    this.ghostNote = false,
    this.grace,
    this.hammer = false,
    this.harmonic,
    this.heavyAccentuatedNote = false,
    this.leftHandFinger = Fingering.open,
    this.letRing = false,
    this.palmMute = false,
    this.rightHandFinger = Fingering.open,
    List<SlideType>? slides,
    this.staccato = false,
    this.tremoloPicking,
    this.trill,
    this.vibrato = false,
  }) : slides = slides ?? <SlideType>[];

  bool get isHarmonic => harmonic != null;

  /// Shallow copy, used where PyGuitarPro calls `attr.evolve(noteEffect)`.
  NoteEffect clone() => NoteEffect(
    accentuatedNote: accentuatedNote,
    bend: bend,
    ghostNote: ghostNote,
    grace: grace,
    hammer: hammer,
    harmonic: harmonic,
    heavyAccentuatedNote: heavyAccentuatedNote,
    leftHandFinger: leftHandFinger,
    letRing: letRing,
    palmMute: palmMute,
    rightHandFinger: rightHandFinger,
    slides: List<SlideType>.from(slides),
    staccato: staccato,
    tremoloPicking: tremoloPicking,
    trill: trill,
    vibrato: vibrato,
  );
}

/// A single note on a string.
class Note {
  final Beat beat;
  int value;
  int velocity;
  int string;
  NoteEffect effect;
  double durationPercent;
  bool swapAccidentals;
  NoteType type;

  // Time-independent duration fields (GP3/4 note flag 0x01).
  int? duration;
  int? tuplet;

  Note(
    this.beat, {
    this.value = 0,
    this.velocity = Velocities.defaultVelocity,
    this.string = 0,
    NoteEffect? effect,
    this.durationPercent = 1.0,
    this.swapAccidentals = false,
    this.type = NoteType.rest,
  }) : effect = effect ?? NoteEffect();

  /// Absolute MIDI value = fret + the open value of the string it's on.
  int get realValue =>
      value + beat.voice.measure.track.strings[string - 1].value;
}

// ---- Chords -------------------------------------------------------------

class Barre {
  int fret;
  int start;
  int end;
  Barre(this.fret, {this.start = 0, this.end = 0});
}

/// A chord diagram annotation on a beat. Read faithfully (so the byte cursor
/// stays aligned) even though the game only needs the fretted notes.
class Chord {
  final int length;
  bool? sharp;
  PitchClass? root;
  ChordType? type;
  ChordExtension? extension;
  PitchClass? bass;
  ChordAlteration? tonality;
  bool? add;
  String name = '';
  ChordAlteration? fifth;
  ChordAlteration? ninth;
  ChordAlteration? eleventh;
  int? firstFret;
  List<int> strings;
  List<Barre> barres = <Barre>[];
  List<bool> omissions = <bool>[];
  List<Fingering> fingerings = <Fingering>[];
  bool? show;
  bool? newFormat;

  Chord(this.length) : strings = List<int>.filled(length, -1);

  /// Fretted strings only (>= 0).
  List<int> get notes => strings.where((s) => s >= 0).toList();
}

// ---- Mix table ----------------------------------------------------------

class MixTableItem {
  int value;
  int duration;
  bool allTracks;
  MixTableItem(this.value, {this.duration = 0, this.allTracks = false});
}

class WahEffect {
  int value;
  bool display;
  WahEffect({this.value = -1, this.display = false});
}

class MixTableChange {
  MixTableItem? instrument;
  RSEInstrument rse = RSEInstrument();
  MixTableItem? volume;
  MixTableItem? balance;
  MixTableItem? chorus;
  MixTableItem? reverb;
  MixTableItem? phaser;
  MixTableItem? tremolo;
  String tempoName = '';
  MixTableItem? tempo;
  bool hideTempo = true;
  WahEffect? wah;
  bool useRSE = false;
}
