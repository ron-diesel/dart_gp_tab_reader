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
  /// Human-readable description of what went wrong.
  final String message;

  /// Creates an exception carrying [message].
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
///
/// A lenient value class: unrecognised on-disk values are preserved in [value]
/// rather than rejected.
class NoteType {
  /// Raw on-disk type tag.
  final int value;

  /// Wraps a raw [value].
  const NoteType(this.value);

  /// A rest (no sounding note).
  static const NoteType rest = NoteType(0);

  /// A normally picked note.
  static const NoteType normal = NoteType(1);

  /// A note tied to the previous one (sustained, not re-picked).
  static const NoteType tie = NoteType(2);

  /// A dead/muted note.
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
  /// Raw on-disk chord-type tag.
  final int value;

  /// Wraps a raw [value].
  const ChordType(this.value);

  /// Major triad.
  static const ChordType major = ChordType(0);

  /// Dominant seventh.
  static const ChordType seventh = ChordType(1);

  /// Major seventh.
  static const ChordType majorSeventh = ChordType(2);

  /// Major sixth.
  static const ChordType sixth = ChordType(3);

  /// Minor triad.
  static const ChordType minor = ChordType(4);

  /// Minor seventh.
  static const ChordType minorSeventh = ChordType(5);

  /// Minor with a major seventh.
  static const ChordType minorMajor = ChordType(6);

  /// Minor sixth.
  static const ChordType minorSixth = ChordType(7);

  /// Suspended second.
  static const ChordType suspendedSecond = ChordType(8);

  /// Suspended fourth.
  static const ChordType suspendedFourth = ChordType(9);

  /// Seventh with a suspended second.
  static const ChordType seventhSuspendedSecond = ChordType(10);

  /// Seventh with a suspended fourth.
  static const ChordType seventhSuspendedFourth = ChordType(11);

  /// Diminished.
  static const ChordType diminished = ChordType(12);

  /// Augmented.
  static const ChordType augmented = ChordType(13);

  /// Power chord (root + fifth).
  static const ChordType power = ChordType(14);

  @override
  bool operator ==(Object other) => other is ChordType && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Chord extension (ninth, eleventh, thirteenth). Lenient.
class ChordExtension {
  /// Raw on-disk extension tag.
  final int value;

  /// Wraps a raw [value].
  const ChordExtension(this.value);

  /// No extension.
  static const ChordExtension none = ChordExtension(0);

  /// Ninth.
  static const ChordExtension ninth = ChordExtension(1);

  /// Eleventh.
  static const ChordExtension eleventh = ChordExtension(2);

  /// Thirteenth.
  static const ChordExtension thirteenth = ChordExtension(3);

  @override
  bool operator ==(Object other) =>
      other is ChordExtension && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// Left/right-hand fingering. Lenient.
class Fingering {
  /// Raw on-disk fingering tag.
  final int value;

  /// Wraps a raw [value].
  const Fingering(this.value);

  /// Open string / no finger.
  static const Fingering open = Fingering(-1);

  /// Thumb (P).
  static const Fingering thumb = Fingering(0);

  /// Index finger (I).
  static const Fingering index = Fingering(1);

  /// Middle finger (M).
  static const Fingering middle = Fingering(2);

  /// Ring finger (A).
  static const Fingering annular = Fingering(3);

  /// Little finger (C).
  static const Fingering little = Fingering(4);

  @override
  bool operator ==(Object other) => other is Fingering && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

// ===========================================================================
// Strict enums
// ===========================================================================

/// Swing/triplet feel applied to a measure.
enum TripletFeel {
  /// Straight (no swing).
  none(0),

  /// Eighth-note swing.
  eighth(1),

  /// Sixteenth-note swing.
  sixteenth(2);

  /// Raw on-disk value.
  final int value;
  const TripletFeel(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static TripletFeel fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown TripletFeel $v'),
  );
}

/// Line-break behaviour for a measure in the score layout.
enum LineBreak {
  /// No forced break.
  none(0),

  /// Force a line break after this measure.
  breakLine(1),

  /// Protect (keep on the same line).
  protect(2);

  /// Raw on-disk value.
  final int value;
  const LineBreak(this.value);

  /// Maps a raw [v] to a member, defaulting to [none] if unknown.
  static LineBreak fromValue(int v) =>
      values.firstWhere((e) => e.value == v, orElse: () => LineBreak.none);
}

/// Stem/beam direction of a voice.
enum VoiceDirection {
  /// Unspecified.
  none(0),

  /// Stems up.
  up(1),

  /// Stems down.
  down(2);

  /// Raw on-disk value.
  final int value;
  const VoiceDirection(this.value);
}

/// Direction of a strum (brush) across the strings.
enum BeatStrokeDirection {
  /// No stroke.
  none(0),

  /// Upstroke (low to high).
  up(1),

  /// Downstroke (high to low).
  down(2);

  /// Raw on-disk value.
  final int value;
  const BeatStrokeDirection(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static BeatStrokeDirection fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown BeatStrokeDirection $v'),
  );
}

/// Bass slap technique on a beat.
enum SlapEffect {
  /// No slap.
  none(0),

  /// Right-hand tapping.
  tapping(1),

  /// Slap (thumb).
  slapping(2),

  /// Pop (pluck).
  popping(3);

  /// Raw on-disk value.
  final int value;
  const SlapEffect(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static SlapEffect fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown SlapEffect $v'),
  );
}

/// Position of a tuplet bracket relative to its group.
enum TupletBracket {
  /// No bracket.
  none(0),

  /// Bracket starts here.
  start(1),

  /// Bracket ends here.
  end(2);

  /// Raw on-disk value.
  final int value;
  const TupletBracket(this.value);
}

/// Octave transposition mark (ottava/quindicesima, up or down).
enum Octave {
  /// No transposition.
  none(0),

  /// 8va (one octave up).
  ottava(1),

  /// 15ma (two octaves up).
  quindicesima(2),

  /// 8vb (one octave down).
  ottavaBassa(3),

  /// 15mb (two octaves down).
  quindicesimaBassa(4);

  /// Raw on-disk value.
  final int value;
  const Octave(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static Octave fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown Octave $v'),
  );
}

/// Whether a beat is empty, a normal beat, or a rest.
enum BeatStatus {
  /// No beat written.
  empty(0),

  /// A normal sounding beat.
  normal(1),

  /// A rest.
  rest(2);

  /// Raw on-disk value.
  final int value;
  const BeatStatus(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static BeatStatus fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown BeatStatus $v'),
  );
}

/// How a grace note transitions into its principal note.
enum GraceEffectTransition {
  /// No transition.
  none(0),

  /// Slide into the note.
  slide(1),

  /// Bend into the note.
  bend(2),

  /// Hammer-on/pull-off into the note.
  hammer(3);

  /// Raw on-disk value.
  final int value;
  const GraceEffectTransition(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static GraceEffectTransition fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown GraceEffectTransition $v'),
  );
}

/// Slide articulation between notes.
enum SlideType {
  /// Slide into the note from above.
  intoFromAbove(-2),

  /// Slide into the note from below.
  intoFromBelow(-1),

  /// No slide.
  none(0),

  /// Shift slide to the next note.
  shiftSlideTo(1),

  /// Legato slide to the next note.
  legatoSlideTo(2),

  /// Slide out and downward.
  outDownwards(3),

  /// Slide out and upward.
  outUpwards(4);

  /// Raw on-disk value.
  final int value;
  const SlideType(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static SlideType fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown SlideType $v'),
  );
}

/// Alteration applied to a chord degree.
enum ChordAlteration {
  /// Perfect / natural.
  perfect(0),

  /// Diminished (flat).
  diminished(1),

  /// Augmented (sharp).
  augmented(2);

  /// Raw on-disk value.
  final int value;
  const ChordAlteration(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static ChordAlteration fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown ChordAlteration $v'),
  );
}

/// Auto-accentuation strength used by the RSE.
enum Accentuation {
  /// No accent.
  none(0),

  /// Very soft.
  verySoft(1),

  /// Soft.
  soft(2),

  /// Medium.
  medium(3),

  /// Strong.
  strong(4),

  /// Very strong.
  veryStrong(5);

  /// Raw on-disk value.
  final int value;
  const Accentuation(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
  static Accentuation fromValue(int v) => values.firstWhere(
    (e) => e.value == v,
    orElse: () => throw GpException('unknown Accentuation $v'),
  );
}

/// Shape of a string bend / whammy-bar event.
enum BendType {
  /// No bend.
  none(0),

  /// Bend up.
  bend(1),

  /// Bend then release.
  bendRelease(2),

  /// Bend, release, bend again.
  bendReleaseBend(3),

  /// Pre-bend (already bent before picking).
  prebend(4),

  /// Pre-bend then release.
  prebendRelease(5),

  /// Whammy dip.
  dip(6),

  /// Whammy dive.
  dive(7),

  /// Whammy release upward.
  releaseUp(8),

  /// Inverted whammy dip.
  invertedDip(9),

  /// Return the bar to neutral.
  returnBar(10),

  /// Whammy release downward.
  releaseDown(11);

  /// Raw on-disk value.
  final int value;
  const BendType(this.value);

  /// Maps a raw [v] to a member, throwing [GpException] if unknown.
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
  /// Lowest preset velocity (pianissimo).
  static const int minVelocity = 15;

  /// Step between successive dynamic presets.
  static const int velocityIncrement = 16;

  /// Pianissimo (ppp).
  static const int pianoPianissimo = minVelocity;

  /// Forte (f).
  static const int forte = minVelocity + velocityIncrement * 5;

  /// Velocity used when none is specified.
  static const int defaultVelocity = forte;
}

// ===========================================================================
// Simple value objects
// ===========================================================================

/// An RGB color (the 4th, blank, byte is dropped on read).
class Color {
  /// Red component (0–255).
  final int r;

  /// Green component (0–255).
  final int g;

  /// Blue component (0–255).
  final int b;

  /// Creates a color from its [r], [g], [b] components.
  const Color(this.r, this.g, this.b);

  /// Solid black.
  static const Color black = Color(0, 0, 0);

  /// Solid red (the default track/marker color).
  static const Color red = Color(255, 0, 0);
}

/// A 2D integer point (e.g. page size in millimetres).
class Point {
  /// Horizontal coordinate.
  final int x;

  /// Vertical coordinate.
  final int y;

  /// Creates a point at ([x], [y]).
  const Point(this.x, this.y);
}

/// Page margins, in the order stored by Guitar Pro.
class Padding {
  /// Right margin.
  final int right;

  /// Top margin.
  final int top;

  /// Left margin.
  final int left;

  /// Bottom margin.
  final int bottom;

  /// Creates padding from its four edges.
  const Padding(this.right, this.top, this.left, this.bottom);
}

/// Key signature, identified by (root, type) where type 0 = major, 1 = minor.
class KeySignature {
  /// Number of sharps (positive) or flats (negative).
  final int root;

  /// 0 = major, 1 = minor.
  final int type;

  /// Creates a key signature from [root] and [type].
  const KeySignature(this.root, this.type);

  @override
  bool operator ==(Object other) =>
      other is KeySignature && other.root == root && other.type == type;
  @override
  int get hashCode => Object.hash(root, type);
}

/// A navigation sign (Coda, Segno, …).
class DirectionSign {
  /// The sign's label.
  final String name;

  /// Creates a sign labelled [name].
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
  /// Diatonic pitch (natural note) in the range 0–11.
  late int just;

  /// Accidental offset (−1 flat, 0 natural, +1 sharp).
  late int accidental;

  /// Chromatic value (`just + accidental`).
  late int value;

  /// Spelling hint, `'flat'` or `'sharp'`.
  late String intonation;

  /// Builds a pitch class from a chromatic/just [just] value, optionally with an
  /// explicit [accidental] and [intonation] spelling.
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
  /// Number of notes actually played.
  int enters;

  /// Number of notes their combined time would normally occupy.
  int times;

  /// Creates a tuplet; defaults to 1:1 (no tuplet).
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
  /// Ticks per quarter note (the time base of the whole model).
  static const int quarterTime = 960;

  /// Whole-note duration value.
  static const int whole = 1;

  /// Half-note duration value.
  static const int half = 2;

  /// Quarter-note duration value.
  static const int quarter = 4;

  /// Eighth-note duration value.
  static const int eighth = 8;

  /// Sixteenth-note duration value.
  static const int sixteenth = 16;

  /// Thirty-second-note duration value.
  static const int thirtySecond = 32;

  /// Sixty-fourth-note duration value.
  static const int sixtyFourth = 64;

  /// Hundred-twenty-eighth-note duration value.
  static const int hundredTwentyEighth = 128;

  /// Base note value (one of the `whole`…`hundredTwentyEighth` constants).
  int value;

  /// Whether the note is dotted (adds half its length).
  bool isDotted;

  /// Tuplet applied to this duration.
  Tuplet tuplet;

  /// Creates a duration, defaulting to a plain quarter note.
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
  /// Beats per measure (top number).
  int numerator;

  /// Beat unit (bottom number), expressed as a [Duration].
  Duration denominator;

  /// Beam grouping pattern.
  List<int> beams;

  /// Creates a time signature, defaulting to 4/4.
  TimeSignature({this.numerator = 4, Duration? denominator, List<int>? beams})
    : denominator = denominator ?? Duration(),
      beams = beams ?? <int>[2, 2, 2, 2];
}

// ===========================================================================
// Headers / markers
// ===========================================================================

/// A section marker shown above a measure.
class Marker {
  /// Marker text.
  String title;

  /// Marker color.
  Color color;

  /// Creates a marker; defaults to a red "Section" label.
  Marker({this.title = 'Section', this.color = Color.red});
}

/// Per-measure metadata shared across tracks.
class MeasureHeader {
  /// 1-based measure number.
  int number;

  /// Start time of the measure, in ticks.
  num start;

  /// Whether the measure ends with a double bar line.
  bool hasDoubleBar;

  /// Key signature in effect.
  KeySignature keySignature;

  /// Time signature in effect.
  TimeSignature timeSignature;

  /// Optional section marker.
  Marker? marker;

  /// Whether a repeat opens at this measure.
  bool isRepeatOpen;

  /// Repeat-alternative ending bitmask.
  int repeatAlternative;

  /// Number of repeats to close here (−1 if none).
  int repeatClose;

  /// Triplet/swing feel for the measure.
  TripletFeel tripletFeel;

  /// Direction sign placed at this measure (e.g. Coda).
  DirectionSign? direction;

  /// "From" direction sign (e.g. Da Capo).
  DirectionSign? fromDirection;

  /// Creates a measure header with Guitar Pro's defaults.
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

  /// Length of the measure in ticks.
  num get length => timeSignature.numerator * timeSignature.denominator.time;

  /// End time of the measure ([start] + [length]).
  num get end => start + length;
}

// ===========================================================================
// Lyrics / page setup / MIDI
// ===========================================================================

/// A single line of lyrics anchored to a measure.
class LyricLine {
  /// Measure this line starts under.
  int startingMeasure;

  /// The lyric text.
  String lyrics;

  /// Creates a lyric line.
  LyricLine({this.startingMeasure = 1, this.lyrics = ''});
}

/// The lyrics block of a song (up to [maxLineCount] lines).
class Lyrics {
  /// Maximum number of lyric lines a song stores.
  static const int maxLineCount = 5;

  /// Index of the track the lyrics follow.
  int trackChoice;

  /// The lyric lines.
  List<LyricLine> lines;

  /// Creates a lyrics block, defaulting to [maxLineCount] empty lines.
  Lyrics({this.trackChoice = 0, List<LyricLine>? lines})
    : lines =
          lines ?? List<LyricLine>.generate(maxLineCount, (_) => LyricLine());
}

/// Score page layout and header/footer templates.
class PageSetup {
  /// Page size in millimetres (default A4 portrait).
  Point pageSize = const Point(210, 297);

  /// Page margins.
  Padding pageMargin = const Padding(10, 15, 10, 10);

  /// Score scaling factor.
  double scoreSizeProportion = 1.0;

  /// Header/footer visibility bitmask.
  int headerAndFooter = 0;

  /// Title template.
  String title = '%title%';

  /// Subtitle template.
  String subtitle = '%subtitle%';

  /// Artist template.
  String artist = '%artist%';

  /// Album template.
  String album = '%album%';

  /// "Words by" template.
  String words = 'Words by %words%';

  /// "Music by" template.
  String music = 'Music by %music%';

  /// "Words & Music by" template.
  String wordsAndMusic = 'Words & Music by %WORDSMUSIC%';

  /// Copyright template.
  String copyright = '';

  /// Page-number template.
  String pageNumber = 'Page %N%/%P%';
}

/// A MIDI channel describing playback for a track.
class MidiChannel {
  /// MIDI channel reserved for percussion.
  static const int defaultPercussionChannel = 9;

  /// Primary MIDI channel.
  int channel;

  /// Secondary (effect) MIDI channel.
  int effectChannel;

  /// General MIDI program number.
  int instrument;

  /// Channel volume (0–127).
  int volume;

  /// Stereo balance (0–127).
  int balance;

  /// Chorus send level.
  int chorus;

  /// Reverb send level.
  int reverb;

  /// Phaser level.
  int phaser;

  /// Tremolo level.
  int tremolo;

  /// Bank-select value.
  int bank;

  /// Creates a MIDI channel with General MIDI defaults.
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

  /// Whether this channel maps to the percussion channel.
  bool get isPercussionChannel => channel % 16 == defaultPercussionChannel;
}

// ===========================================================================
// RSE (Realistic Sound Engine) structures
// ===========================================================================

/// A graphic equaliser used by the Realistic Sound Engine.
class RSEEqualizer {
  /// Per-band gain knobs.
  List<double> knobs;

  /// Overall output gain.
  double gain;

  /// Creates an equaliser.
  RSEEqualizer({List<double>? knobs, this.gain = 0.0})
    : knobs = knobs ?? <double>[];
}

/// The song-level RSE master effect.
class RSEMasterEffect {
  /// Master volume.
  double volume;

  /// Master reverb preset.
  int reverb;

  /// Master equaliser.
  RSEEqualizer equalizer;

  /// Creates a master effect with a 10-band equaliser by default.
  RSEMasterEffect({this.volume = 0, this.reverb = 0, RSEEqualizer? equalizer})
    : equalizer = equalizer ?? RSEEqualizer(knobs: List.filled(10, 0.0));
}

/// An RSE instrument/effect selection.
class RSEInstrument {
  /// Instrument id.
  int instrument;

  /// Reserved/unknown field carried for round-tripping.
  int unknown;

  /// Sound bank id.
  int soundBank;

  /// Effect preset number.
  int effectNumber;

  /// Effect category name.
  String effectCategory;

  /// Effect name.
  String effect;

  /// Creates an RSE instrument with "unset" (−1) defaults.
  RSEInstrument({
    this.instrument = -1,
    this.unknown = -1,
    this.soundBank = -1,
    this.effectNumber = -1,
    this.effectCategory = '',
    this.effect = '',
  });
}

/// Per-track RSE settings.
class TrackRSE {
  /// The track's RSE instrument.
  RSEInstrument instrument;

  /// The track's equaliser.
  RSEEqualizer equalizer;

  /// Humanize amount.
  int humanize;

  /// Auto-accentuation strength.
  Accentuation autoAccentuation;

  /// Creates per-track RSE settings with a 3-band equaliser by default.
  TrackRSE({
    RSEInstrument? instrument,
    RSEEqualizer? equalizer,
    this.humanize = 0,
    this.autoAccentuation = Accentuation.none,
  }) : instrument = instrument ?? RSEInstrument(),
       equalizer = equalizer ?? RSEEqualizer(knobs: List.filled(3, 0.0));
}

/// Notation/diagram display options for a track.
class TrackSettings {
  /// Show tablature staff.
  bool tablature = true;

  /// Show standard notation staff.
  bool notation = true;

  /// Place chord diagrams below the staff.
  bool diagramsAreBelow = false;

  /// Show rhythm slashes.
  bool showRhythm = false;

  /// Force horizontal layout.
  bool forceHorizontal = false;

  /// Force per-beat channels.
  bool forceChannels = false;

  /// Show the chord-diagram list.
  bool diagramList = true;

  /// Show diagrams inline in the score.
  bool diagramsInScore = false;

  /// Auto let-ring.
  bool autoLetRing = false;

  /// Auto brush (strum).
  bool autoBrush = false;

  /// Extend rhythmic durations.
  bool extendRhythmic = false;
}

// ===========================================================================
// Song / Track / Measure / Voice / Beat / Note
// ===========================================================================

/// Top-level node of the song model.
class Song {
  /// Raw version string from the file header.
  String? version;

  /// Parsed version as a `[major, minor, ...]` tuple.
  List<int>? versionTuple;

  /// Clipboard metadata when the data came from a copy/paste fragment.
  Clipboard? clipboard;

  /// Song title.
  String title = '';

  /// Song subtitle.
  String subtitle = '';

  /// Performing artist.
  String artist = '';

  /// Album name.
  String album = '';

  /// Lyricist.
  String words = '';

  /// Composer.
  String music = '';

  /// Copyright notice.
  String copyright = '';

  /// Tab author.
  String tab = '';

  /// Performance instructions.
  String instructions = '';

  /// Free-text notice lines.
  List<String> notice = <String>[];

  /// Lyrics block.
  Lyrics lyrics = Lyrics();

  /// Page layout settings.
  PageSetup pageSetup = PageSetup();

  /// Human-readable tempo label.
  String tempoName = 'Moderate';

  /// Tempo in beats per minute.
  int tempo = 120;

  /// Whether the tempo marking is hidden.
  bool hideTempo = false;

  /// Global key signature.
  KeySignature key = const KeySignature(0, 0);

  /// Shared measure headers (one per measure).
  List<MeasureHeader> measureHeaders;

  /// The song's tracks.
  List<Track> tracks;

  /// Song-level RSE master effect.
  RSEMasterEffect masterEffect = RSEMasterEffect();

  /// Creates an empty song.
  Song({List<MeasureHeader>? measureHeaders, List<Track>? tracks})
    : measureHeaders = measureHeaders ?? <MeasureHeader>[],
      tracks = tracks ?? <Track>[];

  /// Appends [header] to [measureHeaders].
  void addMeasureHeader(MeasureHeader header) {
    measureHeaders.add(header);
  }
}

/// Clipboard fragment bounds, present when a song is a copied selection.
class Clipboard {
  /// First copied measure.
  int startMeasure = 1;

  /// Last copied measure.
  int stopMeasure = 1;

  /// First copied track.
  int startTrack = 1;

  /// Last copied track.
  int stopTrack = 1;

  /// First copied beat.
  int startBeat = 1;

  /// Last copied beat.
  int stopBeat = 1;

  /// Whether the copy spans partial bars.
  bool subBarCopy = false;
}

/// A guitar string with its open-note MIDI value.
class GuitarString {
  /// 1-based string number (1 = highest-pitched string).
  final int number;

  /// MIDI value of the open string.
  final int value;

  /// Creates a string from its [number] and open [value].
  const GuitarString(this.number, this.value);
}

/// A track: a sequence of measures on a tuned instrument.
class Track {
  /// The song this track belongs to.
  final Song song;

  /// 1-based track number.
  int number;

  /// Number of frets on the instrument.
  int fretCount;

  /// Capo / transposition offset.
  int offset;

  /// Whether this is a percussion track.
  bool isPercussionTrack;

  /// Whether this is a 12-string guitar track.
  bool is12StringedGuitarTrack;

  /// Whether this is a banjo track.
  bool isBanjoTrack;

  /// Whether the track is visible.
  bool isVisible;

  /// Whether the track is soloed.
  bool isSolo;

  /// Whether the track is muted.
  bool isMute;

  /// Whether to display the tuning.
  bool indicateTuning;

  /// Track name.
  String name;

  /// The track's measures.
  List<Measure> measures;

  /// Open strings (tuning), highest-pitched first.
  List<GuitarString> strings;

  /// MIDI port.
  int port;

  /// MIDI channel/playback settings.
  MidiChannel channel;

  /// Track color.
  Color color;

  /// Notation/diagram display settings.
  TrackSettings settings;

  /// Whether the Realistic Sound Engine is used.
  bool useRSE;

  /// Per-track RSE settings.
  TrackRSE rse;

  /// Primary clef transposition, if any.
  int? clefTranspose;

  /// Secondary clef transposition, if any.
  int? clefTransposeSecondary;

  /// Creates a track owned by [song] with Guitar Pro defaults.
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
  /// Number of voices a measure holds.
  static const int maxVoices = 2;

  /// The track this measure belongs to.
  final Track track;

  /// The shared header describing this measure.
  final MeasureHeader header;

  /// The measure's voices.
  List<Voice> voices;

  /// Line-break behaviour after this measure.
  LineBreak lineBreak;

  /// Creates a measure, filling in [maxVoices] empty voices if none are given.
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

  /// 1-based measure number (from the header).
  int get number => header.number;

  /// Start time in ticks (from the header).
  num get start => header.start;

  /// End time in ticks (from the header).
  num get end => header.end;

  /// Length in ticks (from the header).
  num get length => header.length;

  /// Time signature in effect (from the header).
  TimeSignature get timeSignature => header.timeSignature;
}

/// A voice: an ordered list of beats within a measure.
class Voice {
  /// The measure this voice belongs to.
  final Measure measure;

  /// The voice's beats, in order.
  List<Beat> beats;

  /// Stem direction.
  VoiceDirection direction;

  /// Creates a voice owned by [measure].
  Voice(this.measure, {List<Beat>? beats, this.direction = VoiceDirection.none})
    : beats = beats ?? <Beat>[];
}

/// A strum (brush) across the strings on a beat.
class BeatStroke {
  /// Strum direction.
  BeatStrokeDirection direction;

  /// Strum speed value.
  int value;

  /// Creates a stroke (defaults to none).
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

/// Effects applied to a whole beat (as opposed to a single note).
class BeatEffect {
  /// Strum across the strings.
  BeatStroke stroke;

  /// Whether a rasgueado is played.
  bool hasRasgueado;

  /// Pick-stroke direction.
  BeatStrokeDirection pickStroke;

  /// Chord diagram attached to the beat.
  Chord? chord;

  /// Whether the beat fades in.
  bool fadeIn;

  /// Whammy-bar event.
  BendEffect? tremoloBar;

  /// Mix-table change triggered on this beat.
  MixTableChange? mixTableChange;

  /// Bass slap technique.
  SlapEffect slapEffect;

  /// Whether vibrato is applied.
  bool vibrato;

  /// Creates a beat effect (all off by default).
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

  /// Whether a chord diagram is attached.
  bool get isChord => chord != null;
}

/// Beaming/layout display options for a beat.
class BeatDisplay {
  /// Break the beam before this beat.
  bool breakBeam = false;

  /// Force a beam through this beat.
  bool forceBeam = false;

  /// Beam stem direction.
  VoiceDirection beamDirection = VoiceDirection.none;

  /// Tuplet bracket position.
  TupletBracket tupletBracket = TupletBracket.none;

  /// Secondary beam-break count.
  int breakSecondary = 0;

  /// Whether the secondary beam break is tuplet-related.
  bool breakSecondaryTuplet = false;

  /// Force a tuplet bracket.
  bool forceBracket = false;
}

/// A beat: a chord/strum of notes sharing a duration.
class Beat {
  /// The voice this beat belongs to.
  final Voice voice;

  /// Notes sounding on this beat.
  List<Note> notes;

  /// The beat's duration.
  Duration duration;

  /// Optional beat text.
  String? text;

  /// Absolute start time in ticks (filled in while reading).
  num? start;

  /// Beat-level effects.
  BeatEffect effect;

  /// Octave transposition mark.
  Octave octave;

  /// Display/beaming options.
  BeatDisplay display;

  /// Whether the beat is empty, normal, or a rest.
  BeatStatus status;

  /// Creates a beat owned by [voice].
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

/// One control point of a bend/whammy curve.
class BendPoint {
  /// Horizontal position along the bend (0–[BendEffect.maxPosition]).
  int position;

  /// Vertical value (pitch offset) at this point.
  int value;

  /// Whether vibrato is applied at this point.
  bool vibrato;

  /// Creates a bend point.
  BendPoint(this.position, this.value, {this.vibrato = false});
}

/// A string bend or whammy-bar effect, described by a list of [points].
class BendEffect {
  /// Pitch change, in raw units, that equals one semitone.
  static const int semitoneLength = 1;

  /// Maximum horizontal position of a bend point.
  static const int maxPosition = 12;

  /// Maximum vertical value of a bend point.
  static const int maxValue = semitoneLength * 12;

  /// Overall bend shape.
  BendType type;

  /// Peak bend value.
  int value;

  /// The bend's control points.
  List<BendPoint> points;

  /// Creates a bend effect (none by default).
  BendEffect({
    this.type = BendType.none,
    this.value = 0,
    List<BendPoint>? points,
  }) : points = points ?? <BendPoint>[];
}

/// A grace note attached to a principal note.
class GraceEffect {
  /// Grace-note duration value.
  int duration;

  /// Fret the grace note is played at.
  int fret;

  /// Whether the grace note is dead/muted.
  bool isDead;

  /// Whether the grace note falls on the beat.
  bool isOnBeat;

  /// How the grace note transitions into the principal note.
  GraceEffectTransition transition;

  /// Grace-note velocity.
  int velocity;

  /// Creates a grace effect.
  GraceEffect({
    this.duration = 32,
    this.fret = 0,
    this.isDead = false,
    this.isOnBeat = false,
    this.transition = GraceEffectTransition.none,
    this.velocity = Velocities.defaultVelocity,
  });
}

/// A trill between the note's fret and another [fret].
class TrillEffect {
  /// The alternate fret.
  int fret;

  /// Duration of each trilled note.
  Duration duration;

  /// Creates a trill effect.
  TrillEffect({this.fret = 0, Duration? duration})
    : duration = duration ?? Duration();
}

/// Tremolo (repeated) picking of a note.
class TremoloPickingEffect {
  /// Duration of each repeated pick.
  Duration duration;

  /// Creates a tremolo-picking effect.
  TremoloPickingEffect({Duration? duration})
    : duration = duration ?? Duration();
}

/// Harmonic effect base — [type] mirrors PyGuitarPro's numeric tag.
class HarmonicEffect {
  /// Numeric harmonic-type tag.
  final int type;

  /// Creates a harmonic effect with raw [type].
  const HarmonicEffect(this.type);
}

/// A natural harmonic, optionally carrying the touch-node [fret] position.
class NaturalHarmonic extends HarmonicEffect {
  /// Touch-node position in frets above the nut (GP7/8 `HFret`, e.g. 12 =
  /// octave node, 5.8 = seventh-partial node), if specified. The binary
  /// GP3-5 formats carry no node — there the notated fret is the touch fret.
  final double? fret;

  /// Creates a natural harmonic.
  const NaturalHarmonic([this.fret]) : super(1);
}

/// An artificial harmonic, optionally targeting a [pitch] and [octave]
/// (GP4/5 files) or a touch-node [fret] distance (GP7/8 files).
class ArtificialHarmonic extends HarmonicEffect {
  /// Target pitch class, if specified.
  final PitchClass? pitch;

  /// Target octave, if specified.
  final Octave? octave;

  /// Touch-node distance in frets above the fretted note (GP7/8 `HFret`,
  /// e.g. 12 = octave node, 5 = two octaves), if specified.
  final double? fret;

  /// Creates an artificial harmonic.
  const ArtificialHarmonic([this.pitch, this.octave, this.fret]) : super(2);
}

/// A tapped harmonic at an optional [fret].
class TappedHarmonic extends HarmonicEffect {
  /// Tapping fret, if specified.
  final int? fret;

  /// Creates a tapped harmonic.
  const TappedHarmonic([this.fret]) : super(3);
}

/// A pinch (artificial) harmonic.
class PinchHarmonic extends HarmonicEffect {
  /// Creates a pinch harmonic.
  const PinchHarmonic() : super(4);
}

/// A semi-harmonic.
class SemiHarmonic extends HarmonicEffect {
  /// Creates a semi-harmonic.
  const SemiHarmonic() : super(5);
}

/// All effects applicable to a single note.
class NoteEffect {
  /// Whether the note is accented.
  bool accentuatedNote;

  /// Bend/whammy effect, if any.
  BendEffect? bend;

  /// Whether the note is a ghost note.
  bool ghostNote;

  /// Grace note, if any.
  GraceEffect? grace;

  /// Whether the note is a hammer-on/pull-off.
  bool hammer;

  /// Harmonic effect, if any.
  HarmonicEffect? harmonic;

  /// Whether the note is heavily accented.
  bool heavyAccentuatedNote;

  /// Left-hand fingering.
  Fingering leftHandFinger;

  /// Whether the note lets ring.
  bool letRing;

  /// Whether the note is palm-muted.
  bool palmMute;

  /// Right-hand fingering.
  Fingering rightHandFinger;

  /// Slides applied to/from the note.
  List<SlideType> slides;

  /// Whether the note is staccato.
  bool staccato;

  /// Tremolo-picking effect, if any.
  TremoloPickingEffect? tremoloPicking;

  /// Trill effect, if any.
  TrillEffect? trill;

  /// Whether vibrato is applied.
  bool vibrato;

  /// Creates a note effect with everything off by default.
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

  /// Whether a harmonic effect is present.
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
  /// The beat this note sounds on.
  final Beat beat;

  /// Fret number (0 = open string).
  int value;

  /// MIDI velocity (0–127).
  int velocity;

  /// 1-based string index (1 = highest-pitched string).
  int string;

  /// Per-note effects.
  NoteEffect effect;

  /// Fraction of the beat the note sounds for.
  double durationPercent;

  /// Whether the accidental spelling is swapped.
  bool swapAccidentals;

  /// Note kind (normal, tie, dead, rest).
  NoteType type;

  /// Time-independent duration value (GP3/4 note flag 0x01), if present.
  int? duration;

  /// Time-independent tuplet value (GP3/4 note flag 0x01), if present.
  int? tuplet;

  /// Creates a note sounding on [beat].
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

/// A barre across several strings at a given [fret].
class Barre {
  /// Fret the barre is held at.
  int fret;

  /// First barred string.
  int start;

  /// Last barred string.
  int end;

  /// Creates a barre.
  Barre(this.fret, {this.start = 0, this.end = 0});
}

/// A chord diagram annotation on a beat. Read faithfully (so the byte cursor
/// stays aligned) even though the game only needs the fretted notes.
class Chord {
  /// Number of strings the diagram covers.
  final int length;

  /// Whether the chord name uses a sharp spelling.
  bool? sharp;

  /// Chord root pitch.
  PitchClass? root;

  /// Chord quality.
  ChordType? type;

  /// Chord extension.
  ChordExtension? extension;

  /// Bass (slash) pitch.
  PitchClass? bass;

  /// Tonality alteration.
  ChordAlteration? tonality;

  /// Whether the extension is an "add".
  bool? add;

  /// Chord name.
  String name = '';

  /// Fifth alteration.
  ChordAlteration? fifth;

  /// Ninth alteration.
  ChordAlteration? ninth;

  /// Eleventh alteration.
  ChordAlteration? eleventh;

  /// Lowest fret of the diagram.
  int? firstFret;

  /// Fret per string (−1 = muted/unplayed).
  List<int> strings;

  /// Barres in the diagram.
  List<Barre> barres = <Barre>[];

  /// Per-string omission flags.
  List<bool> omissions = <bool>[];

  /// Per-string fingerings.
  List<Fingering> fingerings = <Fingering>[];

  /// Whether the diagram is shown.
  bool? show;

  /// Whether the chord uses the newer on-disk format.
  bool? newFormat;

  /// Creates a chord diagram spanning [length] strings (all muted initially).
  Chord(this.length) : strings = List<int>.filled(length, -1);

  /// Fretted strings only (>= 0).
  List<int> get notes => strings.where((s) => s >= 0).toList();
}

// ---- Mix table ----------------------------------------------------------

/// A single mix-table change (value + transition duration).
class MixTableItem {
  /// New value being applied.
  int value;

  /// Transition duration, in beats.
  int duration;

  /// Whether the change applies to all tracks.
  bool allTracks;

  /// Creates a mix-table item.
  MixTableItem(this.value, {this.duration = 0, this.allTracks = false});
}

/// A wah-wah pedal change.
class WahEffect {
  /// Pedal position (−1 = none).
  int value;

  /// Whether the wah marker is displayed.
  bool display;

  /// Creates a wah effect.
  WahEffect({this.value = -1, this.display = false});
}

/// A mix-table change event applied at a beat.
class MixTableChange {
  /// Instrument change.
  MixTableItem? instrument;

  /// RSE instrument change.
  RSEInstrument rse = RSEInstrument();

  /// Volume change.
  MixTableItem? volume;

  /// Balance change.
  MixTableItem? balance;

  /// Chorus change.
  MixTableItem? chorus;

  /// Reverb change.
  MixTableItem? reverb;

  /// Phaser change.
  MixTableItem? phaser;

  /// Tremolo change.
  MixTableItem? tremolo;

  /// New tempo label.
  String tempoName = '';

  /// Tempo change.
  MixTableItem? tempo;

  /// Whether the tempo marking is hidden.
  bool hideTempo = true;

  /// Wah change.
  WahEffect? wah;

  /// Whether RSE values are used.
  bool useRSE = false;
}
