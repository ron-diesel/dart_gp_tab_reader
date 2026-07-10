# dart_gp_tab_reader

[![pub package](https://img.shields.io/pub/v/dart_gp_tab_reader.svg)](https://pub.dev/packages/dart_gp_tab_reader)
[![License: LGPL v3](https://img.shields.io/badge/license-LGPL--3.0-blue.svg)](LICENSE)

A pure-Dart, **read-only** reader for Guitar Pro tablature files — **GP3, GP4,
GP5**, **GP6 (`.gpx`)** and **GP7/GP8 (`.gp`)**.

The GP3–5 binary readers are a Dart port of
[PyGuitarPro](https://github.com/Perlence/PyGuitarPro) by Sviatoslav Abakumov,
which is itself a port of [AlphaTab](https://github.com/CoderLine/alphaTab) /
[TuxGuitar](https://sourceforge.net/projects/tuxguitar/); the binary format
parsing logic mirrors PyGuitarPro closely. GP6–8 files carry a GPIF
(`score.gpif`) XML score inside a container — a zip archive for `.gp`, the
proprietary BCFS/BCFZ filesystem for `.gpx` (decoder ported from alphaTab) —
and are parsed into the same model tree, so callers don't need to care which
format a file came in: `parseGp` detects it from the bytes.

## Usage

```dart
import 'dart:io';
import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart';

void main() {
  final bytes = File('song.gp5').readAsBytesSync();
  final Song song = parseGp(bytes);

  print('${song.title} — ${song.artist} @ ${song.tempo} bpm');
  for (final track in song.tracks) {
    print('Track: ${track.name} (${track.strings.length} strings)');
  }
}
```

See [`example/example.dart`](example/example.dart) for a runnable version.

The returned `Song` is a tree of `Track` → `Measure` → `Voice` → `Beat` →
`Note`. Durations are expressed in ticks (`Duration.quarterTime == 960` per
quarter note); convert to seconds against `Song.tempo` if you need wall-clock
timing.

## License

Because this is a derivative of PyGuitarPro, it is distributed under the
**GNU LGPL-3.0** (see [LICENSE](LICENSE)). It is intentionally kept as a separate
package: an application may depend on it (e.g. via a normal pub dependency)
without the LGPL extending to the application's own proprietary code, as long as
this package's source remains available and replaceable.

Original work © Sviatoslav Abakumov and the PyGuitarPro contributors.

## Trademark notice

"Guitar Pro" is a registered trademark of Arobas Music. This project is an
independent, unofficial reader for the Guitar Pro file format and is **not
affiliated with, endorsed by, or sponsored by Arobas Music**. The name is used
only descriptively to identify the supported file format.
