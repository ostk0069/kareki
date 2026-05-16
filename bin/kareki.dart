import 'dart:io';

import 'package:kareki/src/cli/cli.dart';

void main(List<String> arguments) {
  final code = runCli(arguments, workingDirectory: Directory.current.path);
  exitCode = code;
}
