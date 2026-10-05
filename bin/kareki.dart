import 'dart:io';

import 'package:kareki/src/cli/cli.dart';

Future<void> main(List<String> arguments) async {
  final code = await runCliAsync(
    arguments,
    workingDirectory: Directory.current.path,
  );
  exitCode = code;
}
