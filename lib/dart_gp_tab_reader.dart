/// A pure-Dart, read-only reader for Guitar Pro tablature files
/// (GP3/GP4/GP5 binary, GP6 `.gpx` and GP7/GP8 `.gp`).
///
/// The GP3–5 binary readers are a port of
/// [PyGuitarPro](https://github.com/Perlence/PyGuitarPro); the GP6–8 readers
/// parse the `score.gpif` XML score out of its container (zip for `.gp`,
/// BCFS/BCFZ for `.gpx`). See [parseGp] for the format-detecting entry point
/// and the `models` types for the song tree.
///
/// Distributed under the GNU LGPL-3.0 (see the package LICENSE).
library;

export 'src/gpif_reader.dart' show parseGp7, parseGpif;
export 'src/gpx_reader.dart' show parseGpx;
export 'src/io.dart' show parseGp;
export 'src/models.dart';
