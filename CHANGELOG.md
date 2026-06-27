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
