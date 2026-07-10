import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'models.dart';

/// Reader for the GPIF notation format used by Guitar Pro 6–8.
///
/// A Guitar Pro 7/8 `.gp` file is a plain zip archive holding
/// `Content/score.gpif` — an XML document with the whole score. Unlike the
/// GP3–5 binary formats (which nest beats inside measures), GPIF stores flat,
/// deduplicated pools of `<Bar>`/`<Voice>`/`<Beat>`/`<Note>`/`<Rhythm>`
/// elements cross-linked by id: the same beat element may be referenced from
/// many bars, so every reference is materialised into a fresh model object
/// here.
///
/// The mapping targets the same [Song] tree the GP3–5 readers produce, so
/// consumers don't need to care which container a file came in.

/// Whether [bytes] start with the zip local-file-header magic (`PK\x03\x04`),
/// i.e. look like a Guitar Pro 7/8 `.gp` archive rather than a GP3–5 binary.
bool looksLikeZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

/// Parses a Guitar Pro 7/8 `.gp` file (a zip archive with
/// `Content/score.gpif` inside) from its raw [bytes] into a [Song].
Song parseGp7(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Exception catch (e) {
    throw GpException('not a readable .gp zip archive: $e');
  }
  ArchiveFile? entry;
  for (final file in archive.files) {
    if (file.name == 'Content/score.gpif') {
      entry = file;
      break;
    }
    if (file.name.endsWith('score.gpif')) entry ??= file;
  }
  if (entry == null) {
    throw const GpException('.gp archive contains no Content/score.gpif');
  }
  return parseGpif(entry.content);
}

/// Parses raw `score.gpif` XML [xmlBytes] (the GPIF score shared by the
/// GP6 `.gpx` and GP7/8 `.gp` containers) into a [Song].
Song parseGpif(Uint8List xmlBytes) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(utf8.decode(xmlBytes));
  } on Exception catch (e) {
    throw GpException('malformed score.gpif XML: $e');
  }
  final root = document.rootElement;
  if (root.name.local != 'GPIF') {
    throw GpException("expected <GPIF> root, found <${root.name.local}>");
  }
  return _GpifReader(root).read();
}

/// Multiplier from a GPIF tempo automation's reference unit to
/// quarter-note BPM (index 1 = eighth … 5 = dotted half), following alphaTab.
const List<double> _tempoUnitFactor = [1, 0.5, 1, 1.5, 2, 3];

/// A `<Automation>` entry (tempo change or sound/program switch).
class _Automation {
  final String type;
  final int bar;
  final double ratio; // position within the bar as a 0..1 fraction
  final double value; // numeric value (tempo)
  final int reference; // tempo unit (see [_tempoUnitFactor])
  final String text; // CDATA value (sound id for `Sound` automations)
  const _Automation(
    this.type,
    this.bar,
    this.ratio,
    this.value,
    this.reference,
    this.text,
  );

  /// Tempo in quarter-note BPM (only meaningful for `Tempo` automations).
  double get quarterBpm =>
      value *
      _tempoUnitFactor[reference >= 1 && reference <= 5 ? reference : 2];
}

/// Per-track data gathered from `<Track>` before the model is built.
class _TrackInfo {
  String name = '';
  List<int> tuning = const []; // open-string MIDI pitches, lowest first
  int capo = 0;
  int program = 25;
  bool isPercussion = false;
  int? primaryChannel;
  int port = 0;
  int volume = 104; // 0-127, from the RSE channel strip when present
  int balance = 64; // 0-127, 64 = centre
  int staffCount = 1;

  /// GM drum keys of the track's percussion articulations, in document order;
  /// a note's `<InstrumentArticulation>` indexes into this list.
  List<int> articulations = const [];

  /// Sound id (`path;name;role`) → GM program, for `Sound` automations.
  Map<String, int> sounds = {};
  List<_Automation> automations = const [];
}

/// One `<MasterBar>`: the per-measure data shared by all tracks.
class _MasterBarInfo {
  int numerator = 4;
  int denominator = 4;
  List<String> barIds = const [];
  bool isRepeatOpen = false;
  int repeatClose = -1;
  bool hasDoubleBar = false;
  bool isAnacrusis = false;
  Marker? marker;
  TripletFeel tripletFeel = TripletFeel.none;
  List<_Automation> automations = const [];
}

class _GpifReader {
  final XmlElement root;
  final Song song = Song();

  final Map<String, XmlElement> _barById = {};
  final Map<String, XmlElement> _voiceById = {};
  final Map<String, XmlElement> _beatById = {};
  final Map<String, XmlElement> _noteById = {};

  /// Rhythm id → factory producing a fresh (mutable) [Duration] per use.
  final Map<String, Duration Function()> _rhythmById = {};

  _GpifReader(this.root);

  Song read() {
    _readVersion();
    _readScore();
    _indexPools();

    final masterAutomations = _readAutomations(
      root.getElement('MasterTrack')?.getElement('Automations'),
    );
    final trackInfos = [
      for (final t
          in root.getElement('Tracks')?.findElements('Track') ??
              const <XmlElement>[])
        _readTrackInfo(t),
    ];
    final masterBars = [
      for (final mb
          in root.getElement('MasterBars')?.findElements('MasterBar') ??
              const <XmlElement>[])
        _readMasterBar(mb),
    ];

    // Tempo automations per master-bar index. Automations attached to a
    // MasterBar directly (some writers do that) already know their bar.
    final tempoByBar = <int, List<_Automation>>{};
    for (final a in masterAutomations) {
      if (a.type == 'Tempo') (tempoByBar[a.bar] ??= []).add(a);
    }
    for (var i = 0; i < masterBars.length; i++) {
      for (final a in masterBars[i].automations) {
        if (a.type == 'Tempo') (tempoByBar[i] ??= []).add(a);
      }
    }
    // The song's base tempo is the automation at the very start (if any).
    final initial = tempoByBar[0]?.where((a) => a.ratio == 0).toList();
    if (initial != null && initial.isNotEmpty) {
      song.tempo = initial.first.quarterBpm.round();
    }

    _buildTracks(trackInfos, masterBars);
    _buildHeadersAndTiming(masterBars);
    _attachTempoAutomations(tempoByBar, masterBars);
    _attachSoundAutomations(trackInfos, masterBars);
    return song;
  }

  // -- top-level sections ---------------------------------------------------

  void _readVersion() {
    final version = _text(root.getElement('GPVersion'));
    if (version.isNotEmpty) {
      song.version = 'GPIF $version';
      song.versionTuple = [
        for (final part in version.split('.')) int.tryParse(part) ?? 0,
      ];
    } else {
      song.version = 'GPIF';
    }
  }

  void _readScore() {
    final score = root.getElement('Score');
    if (score == null) return;
    song.title = _text(score.getElement('Title'));
    song.subtitle = _text(score.getElement('SubTitle'));
    song.artist = _text(score.getElement('Artist'));
    song.album = _text(score.getElement('Album'));
    song.words = _text(score.getElement('Words'));
    song.music = _text(score.getElement('Music'));
    song.copyright = _text(score.getElement('Copyright'));
    song.tab = _text(score.getElement('Tabber'));
    song.instructions = _text(score.getElement('Instructions'));
    final notices = _text(score.getElement('Notices'));
    if (notices.isNotEmpty) song.notice = notices.split('\n');
  }

  void _indexPools() {
    void index(String section, String child, Map<String, XmlElement> into) {
      for (final el
          in root.getElement(section)?.findElements(child) ??
              const <XmlElement>[]) {
        final id = el.getAttribute('id');
        if (id != null) into[id] = el;
      }
    }

    index('Bars', 'Bar', _barById);
    index('Voices', 'Voice', _voiceById);
    index('Beats', 'Beat', _beatById);
    index('Notes', 'Note', _noteById);
    for (final el
        in root.getElement('Rhythms')?.findElements('Rhythm') ??
            const <XmlElement>[]) {
      final id = el.getAttribute('id');
      if (id != null) _rhythmById[id] = _rhythmFactory(el);
    }
  }

  /// Parses a `<Rhythm>` into a factory of fresh [Duration]s ([Duration] is
  /// mutable, and one rhythm is shared by many beats).
  Duration Function() _rhythmFactory(XmlElement el) {
    // `Long`/`DoubleWhole` (and 256th) can't be represented by the GP3-5
    // model's power-of-two range — clamp to the nearest supported value.
    const values = {
      'Long': Duration.whole,
      'DoubleWhole': Duration.whole,
      'Whole': Duration.whole,
      'Half': Duration.half,
      'Quarter': Duration.quarter,
      'Eighth': Duration.eighth,
      '16th': Duration.sixteenth,
      '32nd': Duration.thirtySecond,
      '64th': Duration.sixtyFourth,
      '128th': Duration.hundredTwentyEighth,
      '256th': Duration.hundredTwentyEighth,
    };
    final value = values[_text(el.getElement('NoteValue'))] ?? Duration.quarter;
    // The model only supports a single dot; a double dot is approximated.
    final dotted =
        (int.tryParse(
              el.getElement('AugmentationDot')?.getAttribute('count') ?? '0',
            ) ??
            0) >=
        1;
    final tuplet = el.getElement('PrimaryTuplet');
    final enters = int.tryParse(tuplet?.getAttribute('num') ?? '') ?? 1;
    final times = int.tryParse(tuplet?.getAttribute('den') ?? '') ?? 1;
    return () => Duration(
      value: value,
      isDotted: dotted,
      tuplet: Tuplet(enters: enters, times: times),
    );
  }

  List<_Automation> _readAutomations(XmlElement? automations) {
    if (automations == null) return const [];
    final result = <_Automation>[];
    for (final el in automations.findElements('Automation')) {
      final valueEl = el.getElement('Value');
      var number = 0.0;
      var reference = 2;
      var text = '';
      if (valueEl != null) {
        final raw = _text(valueEl);
        final parts = raw.split(RegExp(r'\s+'));
        final first = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
        if (first != null) {
          number = first;
          reference = parts.length > 1
              ? (int.tryParse(parts[1]) ?? 2)
              : reference;
        } else {
          text = raw; // CDATA sound id like "path;name;role"
        }
      }
      result.add(
        _Automation(
          _text(el.getElement('Type')),
          int.tryParse(_text(el.getElement('Bar'))) ?? 0,
          double.tryParse(_text(el.getElement('Position'))) ?? 0,
          number,
          reference,
          text,
        ),
      );
    }
    return result;
  }

  _TrackInfo _readTrackInfo(XmlElement el) {
    final info = _TrackInfo();
    info.name = _text(el.getElement('Name'));

    // Tuning and capo live in staff (GP7/8) or track (GP6) properties.
    for (final prop in el.findAllElements('Property')) {
      switch (prop.getAttribute('name')) {
        case 'Tuning':
          if (info.tuning.isEmpty) {
            info.tuning = [
              for (final p in _text(
                prop.getElement('Pitches'),
              ).split(RegExp(r'\s+')))
                if (int.tryParse(p) != null) int.parse(p),
            ];
          }
        case 'CapoFret':
          info.capo = int.tryParse(_text(prop.getElement('Fret'))) ?? 0;
      }
    }

    info.staffCount =
        el.getElement('Staves')?.findElements('Staff').length ?? 1;
    if (info.staffCount < 1) info.staffCount = 1;

    // GM program: GP7/8 keeps it per <Sound>, GP6 under <GeneralMidi>.
    var firstSound = true;
    for (final sound
        in el.getElement('Sounds')?.findElements('Sound') ??
            const <XmlElement>[]) {
      final program = int.tryParse(
        _text(sound.getElement('MIDI')?.getElement('Program')),
      );
      if (program == null) continue;
      final id =
          '${_text(sound.getElement('Path'))};'
          '${_text(sound.getElement('Name'))};'
          '${_text(sound.getElement('Role'))}';
      info.sounds[id] = program;
      if (firstSound) {
        info.program = program;
        firstSound = false;
      }
    }
    final generalMidi = el.getElement('GeneralMidi');
    if (generalMidi != null) {
      if (firstSound) {
        info.program =
            int.tryParse(_text(generalMidi.getElement('Program'))) ??
            info.program;
      }
      info.primaryChannel = int.tryParse(
        _text(generalMidi.getElement('PrimaryChannel')),
      );
      if (generalMidi.getAttribute('table') == 'Percussion') {
        info.isPercussion = true;
      }
    }
    final connection = el.getElement('MidiConnection');
    if (connection != null) {
      info.primaryChannel ??= int.tryParse(
        _text(connection.getElement('PrimaryChannel')),
      );
      info.port = int.tryParse(_text(connection.getElement('Port'))) ?? 0;
    }

    final instrumentSet = el.getElement('InstrumentSet');
    final setType = _text(instrumentSet?.getElement('Type'));
    if (setType.toLowerCase().contains('drum') || info.primaryChannel == 9) {
      info.isPercussion = true;
    }
    // Percussion articulations: a note's <InstrumentArticulation> indexes into
    // this list, whose <OutputMidiNumber> is the GM drum key to sound.
    if (instrumentSet != null) {
      info.articulations = [
        for (final a in instrumentSet.findAllElements('Articulation'))
          int.tryParse(_text(a.getElement('OutputMidiNumber'))) ?? 0,
      ];
    }

    // Mixer defaults from the RSE channel strip (floats 0..1; index 11 = pan,
    // 12 = volume — same slots alphaTab reads).
    final parameters = _text(
      el
          .getElement('RSE')
          ?.getElement('ChannelStrip')
          ?.getElement('Parameters'),
    ).split(RegExp(r'\s+'));
    if (parameters.length > 12) {
      final pan = double.tryParse(parameters[11]);
      final volume = double.tryParse(parameters[12]);
      if (pan != null) info.balance = (pan * 127).round().clamp(0, 127);
      if (volume != null) info.volume = (volume * 127).round().clamp(0, 127);
    }

    info.automations = _readAutomations(el.getElement('Automations'));
    return info;
  }

  _MasterBarInfo _readMasterBar(XmlElement el) {
    final info = _MasterBarInfo();
    final time = _text(el.getElement('Time')).split('/');
    if (time.length == 2) {
      info.numerator = int.tryParse(time[0]) ?? 4;
      info.denominator = int.tryParse(time[1]) ?? 4;
    }
    info.barIds = _text(el.getElement('Bars')).split(RegExp(r'\s+'));
    info.isAnacrusis = el.getElement('Anacrusis') != null;
    info.hasDoubleBar = el.getElement('DoubleBar') != null;
    final repeat = el.getElement('Repeat');
    if (repeat != null) {
      info.isRepeatOpen = repeat.getAttribute('start') == 'true';
      if (repeat.getAttribute('end') == 'true') {
        info.repeatClose =
            int.tryParse(repeat.getAttribute('count') ?? '') ?? 2;
      }
    }
    final section = el.getElement('Section');
    if (section != null) {
      final text = _text(section.getElement('Text'));
      final letter = _text(section.getElement('Letter'));
      info.marker = Marker(title: text.isNotEmpty ? text : letter);
    }
    switch (_text(el.getElement('TripletFeel'))) {
      case 'Triplet8th':
        info.tripletFeel = TripletFeel.eighth;
      case 'Triplet16th':
        info.tripletFeel = TripletFeel.sixteenth;
    }
    info.automations = _readAutomations(el.getElement('Automations'));
    return info;
  }

  // -- model building ---------------------------------------------------------

  /// Builds tracks, measures, voices, beats and notes. Beat [Beat.start] is
  /// filled with the offset *within its measure*; [_buildHeadersAndTiming]
  /// later rebases it to absolute ticks once every header start is known.
  void _buildTracks(List<_TrackInfo> infos, List<_MasterBarInfo> masterBars) {
    // Headers are shared across tracks; created here, timed later.
    for (var i = 0; i < masterBars.length; i++) {
      final mb = masterBars[i];
      song.addMeasureHeader(
        MeasureHeader(
          number: i + 1,
          timeSignature: TimeSignature(
            numerator: mb.numerator,
            denominator: Duration(value: mb.denominator),
          ),
          isRepeatOpen: mb.isRepeatOpen,
          repeatClose: mb.repeatClose,
          hasDoubleBar: mb.hasDoubleBar,
          marker: mb.marker,
          tripletFeel: mb.tripletFeel,
        ),
      );
    }

    // A master bar lists one bar id per *staff*, tracks in order; precompute
    // each track's offset into that list.
    final staffOffsets = <int>[];
    var offset = 0;
    for (final info in infos) {
      staffOffsets.add(offset);
      offset += info.staffCount;
    }

    for (var ti = 0; ti < infos.length; ti++) {
      final info = infos[ti];
      final stringCount = info.tuning.length;
      final track = Track(
        song,
        number: ti + 1,
        name: info.name.isEmpty ? 'Track ${ti + 1}' : info.name,
        offset: info.capo,
        isPercussionTrack: info.isPercussion,
        strings: [
          // The model numbers strings 1..N from the highest-pitched string;
          // GPIF lists open pitches lowest-first.
          for (var n = 1; n <= stringCount; n++)
            GuitarString(n, info.tuning[stringCount - n]),
        ],
        port: info.port,
        channel: MidiChannel(
          channel: info.isPercussion
              ? MidiChannel.defaultPercussionChannel
              : (info.primaryChannel ?? 0),
          instrument: info.program,
          volume: info.volume,
          balance: info.balance,
        ),
      );
      song.tracks.add(track);

      for (var mi = 0; mi < masterBars.length; mi++) {
        final header = song.measureHeaders[mi];
        final measure = Measure(track, header);
        final voices = <Voice>[];
        // Merge the voices of all of the track's staves into one measure
        // (multi-staff parts — e.g. grand-staff keys — play as one part).
        for (var si = 0; si < info.staffCount; si++) {
          final barIndex = staffOffsets[ti] + si;
          if (barIndex >= masterBars[mi].barIds.length) break;
          final bar = _barById[masterBars[mi].barIds[barIndex]];
          if (bar == null) continue;
          for (final voiceId in _text(
            bar.getElement('Voices'),
          ).split(RegExp(r'\s+'))) {
            final voiceEl = _voiceById[voiceId];
            if (voiceId == '-1' || voiceEl == null) continue;
            voices.add(_readVoice(voiceEl, measure, info));
          }
        }
        if (voices.isNotEmpty) measure.voices = voices;
        track.measures.add(measure);
      }
    }
  }

  Voice _readVoice(XmlElement el, Measure measure, _TrackInfo info) {
    final voice = Voice(measure);
    num tick = 0;
    for (final beatId in _text(el.getElement('Beats')).split(RegExp(r'\s+'))) {
      final beatEl = _beatById[beatId];
      if (beatEl == null) continue;
      // Grace beats are ornaments that consume no bar time; including their
      // rhythm would shift every later beat, so they are skipped.
      if (beatEl.getElement('GraceNotes') != null) continue;
      final beat = _readBeat(beatEl, voice, info);
      beat.start = tick; // measure-relative; rebased in _buildHeadersAndTiming
      voice.beats.add(beat);
      tick += beat.duration.time;
    }
    return voice;
  }

  Beat _readBeat(XmlElement el, Voice voice, _TrackInfo info) {
    final rhythmId = el.getElement('Rhythm')?.getAttribute('ref');
    final beat = Beat(
      voice,
      duration: _rhythmById[rhythmId]?.call() ?? Duration(),
    );

    final velocity = _velocityOf(_text(el.getElement('Dynamic')));
    for (final prop
        in el.getElement('Properties')?.findElements('Property') ??
            const <XmlElement>[]) {
      switch (prop.getAttribute('name')) {
        case 'VibratoWTremBar':
          beat.effect.vibrato = true;
        case 'Slapped':
          if (prop.getElement('Enable') != null) {
            beat.effect.slapEffect = SlapEffect.slapping;
          }
        case 'Popped':
          if (prop.getElement('Enable') != null) {
            beat.effect.slapEffect = SlapEffect.popping;
          }
      }
    }

    final noteIds = _text(el.getElement('Notes'));
    if (noteIds.isNotEmpty) {
      for (final noteId in noteIds.split(RegExp(r'\s+'))) {
        final noteEl = _noteById[noteId];
        if (noteEl == null) continue;
        beat.notes.add(_readNote(noteEl, beat, info, velocity));
      }
    }
    beat.status = beat.notes.isEmpty ? BeatStatus.rest : BeatStatus.normal;
    return beat;
  }

  Note _readNote(XmlElement el, Beat beat, _TrackInfo info, int velocity) {
    final note = Note(beat, type: NoteType.normal, velocity: velocity);
    int? gpifString;
    int? fret;
    int? midi;
    var element = -1;
    var variation = 0;

    for (final prop
        in el.getElement('Properties')?.findElements('Property') ??
            const <XmlElement>[]) {
      switch (prop.getAttribute('name')) {
        case 'String':
          gpifString = int.tryParse(_text(prop.getElement('String')));
        case 'Fret':
          fret = int.tryParse(_text(prop.getElement('Fret')));
        case 'Midi':
          midi = int.tryParse(_text(prop.getElement('Number')));
        case 'Muted':
          if (prop.getElement('Enable') != null) note.type = NoteType.dead;
        case 'PalmMuted':
          if (prop.getElement('Enable') != null) note.effect.palmMute = true;
        case 'LetRing':
          if (prop.getElement('Enable') != null) note.effect.letRing = true;
        case 'HopoOrigin':
          if (prop.getElement('Enable') != null) note.effect.hammer = true;
        case 'Tapped':
          if (prop.getElement('Enable') != null) {
            beat.effect.slapEffect = SlapEffect.tapping;
          }
        case 'Slide':
          final flags = int.tryParse(_text(prop.getElement('Flags'))) ?? 0;
          note.effect.slides = _slidesFromFlags(flags);
        case 'Bended':
          if (prop.getElement('Enable') != null) {
            note.effect.bend ??= BendEffect(type: BendType.bend);
          }
        case 'BendDestinationValue':
          final value = double.tryParse(_text(prop.getElement('Float')));
          if (value != null) {
            // GPIF bend values share the GP3-5 raw scale (100 = full bend);
            // keep `value` raw and scale points like the binary readers do.
            final bend = note.effect.bend ??= BendEffect(type: BendType.bend);
            bend.value = value.round();
            bend.points = [
              BendPoint(0, 0),
              BendPoint(BendEffect.maxPosition, (value / 25).round()),
            ];
          }
        case 'HarmonicType':
          note.effect.harmonic = _harmonicOf(_text(prop.getElement('HType')));
        // GP6 percussion: drum sound as an element/variation pair.
        case 'Element':
          element = int.tryParse(_text(prop.getElement('Element'))) ?? -1;
        case 'Variation':
          variation = int.tryParse(_text(prop.getElement('Variation'))) ?? 0;
      }
    }

    for (final child in el.childElements) {
      switch (child.name.local) {
        case 'Tie':
          if (child.getAttribute('destination') == 'true') {
            note.type = NoteType.tie;
          }
        case 'Vibrato':
          note.effect.vibrato = true;
        case 'LetRing':
          note.effect.letRing = true;
        case 'AntiAccent':
          note.effect.ghostNote = true;
      }
    }

    if (info.isPercussion) {
      // Percussion pitch: GP7/8 notes carry an <InstrumentArticulation> index
      // into the track's articulation table; GP6 notes an element/variation
      // pair. Either way the result is a GM drum key stored in `value`.
      final articulation =
          int.tryParse(_text(el.getElement('InstrumentArticulation'))) ?? -1;
      note.string = 0;
      if (articulation >= 0 && articulation < info.articulations.length) {
        note.value = info.articulations[articulation];
      } else if (element >= 0) {
        note.value = _gm(element, variation);
      } else {
        note.value = midi ?? fret ?? 0;
      }
    } else if (gpifString != null && info.tuning.isNotEmpty) {
      // GPIF numbers strings 0..N-1 lowest-first; the model 1..N highest-first.
      note.string = info.tuning.length - gpifString;
      note.value = fret ?? (midi != null ? midi - info.tuning[gpifString] : 0);
    } else {
      // No tablature staff (keys, etc.) — keep the raw MIDI pitch in `value`
      // with string 0, the convention consumers use for pitch-only notes.
      note.string = 0;
      note.value = midi ?? fret ?? 0;
    }
    return note;
  }

  /// Maps GPIF slide bit flags to the model's [SlideType]s (same bit layout
  /// alphaTab decodes: 1 shift, 2 legato, 4/8 out, 16/32 in, 64/128 pick).
  List<SlideType> _slidesFromFlags(int flags) => [
    if (flags & 1 != 0) SlideType.shiftSlideTo,
    if (flags & 2 != 0) SlideType.legatoSlideTo,
    if (flags & 4 != 0) SlideType.outDownwards,
    if (flags & 8 != 0) SlideType.outUpwards,
    if (flags & 16 != 0) SlideType.intoFromBelow,
    if (flags & 32 != 0) SlideType.intoFromAbove,
    if (flags & 64 != 0) SlideType.outDownwards,
    if (flags & 128 != 0) SlideType.outUpwards,
  ];

  /// GM drum keys for GP6 percussion element/variation pairs (rows =
  /// elements, columns = variations 0..2), derived from alphaTab's GP6
  /// table with its extended articulation ids folded back to plain GM keys
  /// (e.g. rim shot → snare 38, half hi-hat → open 46, ride bell → 53).
  static const List<List<int>> _gp6DrumKeys = [
    [35, 35, 35], // 0 kick (hit)
    [38, 38, 37], // 1 snare (hit, rim shot, side stick)
    [56, 56, 56], // 2 cowbell low (hit, tip)
    [56, 56, 56], // 3 cowbell medium (hit, tip)
    [56, 56, 56], // 4 cowbell high (hit, tip)
    [43, 43, 43], // 5 tom very low
    [45, 45, 45], // 6 tom low
    [47, 47, 47], // 7 tom medium
    [48, 48, 48], // 8 tom high
    [50, 50, 50], // 9 tom very high
    [42, 46, 46], // 10 hi-hat (closed, half, open)
    [44, 44, 44], // 11 pedal hi-hat
    [57, 57, 57], // 12 crash medium (hit, choke)
    [49, 49, 49], // 13 crash high (hit, choke)
    [55, 55, 55], // 14 splash (hit, choke)
    [51, 51, 53], // 15 ride (middle, edge, bell)
    [52, 52, 52], // 16 china (hit, choke)
  ];

  static int _gm(int element, int variation) {
    if (element < 0 || element >= _gp6DrumKeys.length) return 38;
    final row = _gp6DrumKeys[element];
    return row[variation < 0 || variation >= row.length ? 0 : variation];
  }

  HarmonicEffect? _harmonicOf(String type) => switch (type) {
    'Natural' => const NaturalHarmonic(),
    'Artificial' => const ArtificialHarmonic(),
    'Tap' => const TappedHarmonic(),
    'Pinch' => const PinchHarmonic(),
    'Semi' || 'Feedback' => const SemiHarmonic(),
    _ => null,
  };

  /// GPIF dynamic marks to MIDI velocity, on the same ppp..fff ladder the
  /// GP3-5 readers use.
  int _velocityOf(String dynamic_) {
    const order = ['PPP', 'PP', 'P', 'MP', 'MF', 'F', 'FF', 'FFF'];
    final index = order.indexOf(dynamic_);
    if (index < 0) return Velocities.defaultVelocity;
    return Velocities.minVelocity + Velocities.velocityIncrement * index;
  }

  /// Assigns header start ticks (first measure starts at
  /// [Duration.quarterTime], like the binary formats) and rebases every
  /// beat's measure-relative [Beat.start] to absolute ticks. An anacrusis
  /// (pickup) bar keeps its notated time signature in the file even though
  /// it's only partially filled, so its signature is rewritten to the actual
  /// content length to keep later measures from drifting.
  void _buildHeadersAndTiming(List<_MasterBarInfo> masterBars) {
    num start = Duration.quarterTime;
    for (var mi = 0; mi < song.measureHeaders.length; mi++) {
      final header = song.measureHeaders[mi];
      if (masterBars[mi].isAnacrusis) {
        num filled = 0;
        for (final track in song.tracks) {
          for (final voice in track.measures[mi].voices) {
            num sum = 0;
            for (final beat in voice.beats) {
              sum += beat.duration.time;
            }
            if (sum > filled) filled = sum;
          }
        }
        if (filled > 0 && filled < header.length) {
          final signature = _signatureForTicks(filled);
          if (signature != null) header.timeSignature = signature;
        }
      }
      header.start = start;
      start += header.length;
      for (final track in song.tracks) {
        for (final voice in track.measures[mi].voices) {
          for (final beat in voice.beats) {
            beat.start = header.start + (beat.start ?? 0);
          }
        }
      }
    }
  }

  /// A time signature whose measure length is exactly [ticks], if one exists
  /// (tried from quarters down to 128ths).
  TimeSignature? _signatureForTicks(num ticks) {
    for (final denominator in const [4, 8, 16, 32, 64, 128]) {
      final unit = Duration.quarterTime * 4 / denominator;
      final beats = ticks / unit;
      if (beats == beats.roundToDouble() && beats >= 1) {
        return TimeSignature(
          numerator: beats.round(),
          denominator: Duration(value: denominator),
        );
      }
    }
    return null;
  }

  /// Attaches tempo automations as [MixTableChange.tempo] events on the first
  /// track's beats (tempo is global in Guitar Pro), at the beat closest to the
  /// automation's position within its bar.
  void _attachTempoAutomations(
    Map<int, List<_Automation>> tempoByBar,
    List<_MasterBarInfo> masterBars,
  ) {
    if (song.tracks.isEmpty) return;
    tempoByBar.forEach((barIndex, automations) {
      for (final automation in automations) {
        if (barIndex == 0 && automation.ratio == 0) continue; // base tempo
        final beat = _beatAt(song.tracks.first, barIndex, automation.ratio);
        if (beat == null) continue;
        final change = beat.effect.mixTableChange ??= MixTableChange();
        change.tempo = MixTableItem(automation.quarterBpm.round());
      }
    });
  }

  /// Attaches per-track `Sound` automations (mid-song program switches, e.g.
  /// clean → distortion) as [MixTableChange.instrument] events.
  void _attachSoundAutomations(
    List<_TrackInfo> infos,
    List<_MasterBarInfo> masterBars,
  ) {
    for (var ti = 0; ti < infos.length && ti < song.tracks.length; ti++) {
      for (final automation in infos[ti].automations) {
        if (automation.type != 'Sound') continue;
        final program = infos[ti].sounds[automation.text];
        if (program == null) continue;
        final beat = _beatAt(song.tracks[ti], automation.bar, automation.ratio);
        if (beat == null) continue;
        final change = beat.effect.mixTableChange ??= MixTableChange();
        change.instrument = MixTableItem(program);
      }
    }
  }

  /// The first beat of [track]'s measure [barIndex] at or after [ratio]
  /// (0..1 position within the bar), searched across its voices.
  Beat? _beatAt(Track track, int barIndex, double ratio) {
    if (barIndex < 0 || barIndex >= track.measures.length) return null;
    final measure = track.measures[barIndex];
    final target = measure.header.start + measure.header.length * ratio;
    Beat? best;
    for (final voice in measure.voices) {
      for (final beat in voice.beats) {
        final start = beat.start;
        if (start == null || start < target - 1) continue;
        if (best == null || start < best.start!) best = beat;
        break; // beats are in time order within a voice
      }
    }
    return best;
  }
}

/// Trimmed inner text of [el] (CDATA included), or '' when absent.
String _text(XmlElement? el) => el?.innerText.trim() ?? '';
