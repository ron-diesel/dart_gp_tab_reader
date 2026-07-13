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
