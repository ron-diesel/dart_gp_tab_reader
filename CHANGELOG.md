## 0.3.3

- GPIF reader: **natural harmonics keep their `HFret` touch node.**
  `NaturalHarmonic` gained an optional `fret` field (absolute node position
  in frets above the nut, e.g. `5.8` = seventh-partial node). Previously the
  node was dropped for natural harmonics, so consumers could only guess the
  sounding partial from the notated fret — which is ambiguous (a harmonic
  notated at fret 6 is the 5.8 node, two-octaves-and-a-seventh above the
  open string, not an octave). GP3-5 files still produce `fret == null`
  (the binary formats carry no node).

## 0.3.2

- GPIF reader: **multi-point bend curves.** The full
  `BendOrigin/Middle/Destination{Value,Offset}` property set is now read
  (mirroring alphaTab's mapping), so bend-releases, pre-bends and held bends
  keep their real shape — previously every bend was flattened to a single
  `0 → destination` linear ramp.
- GPIF reader: **whammy bar.** Both the GP7/8 `WhammyBar*` beat properties
  and the GP6 `<Whammy>` attribute form now land on
  `BeatEffect.tremoloBar` with the same multi-point curve; whammy gestures
  in `.gp`/`.gpx` files were previously dropped entirely.
- GPIF reader: **tremolo picking** (`<Tremolo>1/2|1/4|1/8</Tremolo>` beat
  element → `NoteEffect.tremoloPicking` at eighth/16th/32nd strokes),
  **trills** (`<Trill>` note element, MIDI value converted to a fret on the
  note's string, 16th period) and **accent flags** (`<Accent>` bit field:
  0x01 staccato, 0x04 heavy accent, 0x08 accent) are now read — all were
  previously dropped.
- GPIF reader: **grace notes.** A `<GraceNotes>` beat's notes now become
  `GraceEffect`s on the matching notes of the following real beat (fret,
  velocity, duration, on/before-beat placement, hammered/slid transition)
  instead of being skipped outright. Bar timing is unchanged (a grace beat
  still consumes no bar time).

## 0.3.1

- GPIF reader: `HarmonicType` values are now matched case-insensitively —
  some GPIF writers emit `artificial`/`natural` lowercase, which previously
  dropped the harmonic entirely. A note with an enabled `Harmonic` property
  but no recognized type now falls back to a natural harmonic instead of
  none.
- GPIF reader: the `HarmonicFret` touch-node distance is now read —
  artificial harmonics carry it in the new `ArtificialHarmonic.fret` field,
  tapped harmonics resolve it to their absolute tap fret
  (`TappedHarmonic.fret`), matching the GP4/5 readers.

## 0.3.0

- **Guitar Pro 6 (`.gpx`) support.** `parseGp` now decodes the proprietary
  BCFS/BCFZ container (`lib/src/gpx_reader.dart`, bit-level LZ decompressor +
  sector filesystem, ported from alphaTab's `GpxFileSystem`) and feeds the
  inner `score.gpif` to the GPIF reader. New export: `parseGpx`.
- GPIF reader: GP6 percussion notes (`Element`/`Variation` properties) are
  now mapped to GM drum keys, matching the GP7/8 articulation handling.

## 0.2.0

- **Guitar Pro 7/8 (`.gp`) support.** `parseGp` now detects the zip-based `.gp`
  container by its bytes and parses the `Content/score.gpif` GPIF XML score
  into the same `Song` tree as the GP3–5 readers. Covered: metadata, tempo
  (incl. mid-song tempo automations, mapped to `MixTableChange.tempo`),
  per-track tuning/capo/GM program/volume/pan, mid-song sound switches
  (`Sound` automations → `MixTableChange.instrument`), percussion articulation
  mapping to GM drum keys, time signatures, repeats, section markers,
  anacrusis (pickup) bars, rests, ties, dead/ghost notes, palm mute, let ring,
  hammer-on/pull-off, slides, bends, harmonics, vibrato, slap/pop/tap and
  dynamics. Grace beats are skipped (they carry no bar time in GPIF).
- New exports: `parseGp7` (zip container) and `parseGpif` (bare `score.gpif`
  XML, useful for GP6 `.gpx` payloads unpacked by other means).
- GP6 `.gpx` (BCFS/BCFZ container) is still not decoded, but is now rejected
  with a clear `GpException` instead of an "unsupported version" error.
- New dependencies: `archive`, `xml`.

## 0.1.1

- Added dartdoc comments across the public API (`models.dart`): every model
  class, enum, constructor and key field is now documented (≈99% coverage).
- No functional changes.

## 0.1.0

- Initial release.
- Pure-Dart, read-only reader for Guitar Pro **GP3**, **GP4** and **GP5** files.
- Parses into a `Song` → `Track` → `Measure` → `Voice` → `Beat` → `Note` tree.
- Dart port of [PyGuitarPro](https://github.com/Perlence/PyGuitarPro); the binary
  parsing logic mirrors it closely. Test fixtures and the reference dump are taken
  from the PyGuitarPro test suite.
