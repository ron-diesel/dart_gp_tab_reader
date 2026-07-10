/// A pure-Dart, read-only reader for Guitar Pro tablature files
/// (GP3/GP4/GP5 binary and GP7/GP8 `.gp`).
///
/// The GP3–5 binary readers are a port of
/// [PyGuitarPro](https://github.com/Perlence/PyGuitarPro); the GP7/8 reader
/// parses the zip-packed `score.gpif` XML score. See [parseGp] for the
/// format-detecting entry point and the `models` types for the song tree.
///
/// Distributed under the GNU LGPL-3.0 (see the package LICENSE).
library;

export 'src/gpif_reader.dart' show parseGp7, parseGpif;
export 'src/io.dart' show parseGp;
export 'src/models.dart';
