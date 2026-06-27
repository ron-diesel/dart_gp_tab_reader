import 'dart:io';

import 'package:dart_gp_tab_reader/dart_gp_tab_reader.dart';

/// Reads a Guitar Pro file (GP3/GP4/GP5) and prints a short summary.
///
/// Usage: `dart run example/example.dart path/to/song.gp5`
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run example/example.dart <song.gp3|gp4|gp5>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final bytes = File(args.first).readAsBytesSync();
  final Song song = parseGp(bytes);

  print('${song.title} — ${song.artist} @ ${song.tempo} bpm');
  for (final track in song.tracks) {
    print(
      '  Track: ${track.name} (${track.strings.length} strings, '
      '${track.measures.length} measures)',
    );
  }
}
