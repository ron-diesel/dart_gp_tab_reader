/// A pure-Dart, read-only reader for Guitar Pro tablature files (GP3/GP4/GP5).
///
/// A port of [PyGuitarPro](https://github.com/Perlence/PyGuitarPro). See
/// [parseGp] for the entry point and the `models` types for the song tree.
///
/// Distributed under the GNU LGPL-3.0 (see the package LICENSE).
library;

export 'src/io.dart' show parseGp;
export 'src/models.dart';
