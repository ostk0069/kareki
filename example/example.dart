// Programmatic use of kareki from Dart code.
//
// Most users will invoke kareki via `dart run kareki`. This example shows
// how to drive the runner from inside another tool.

import 'package:kareki/kareki.dart';

Future<void> main() async {
  const root = '.';
  final config = KarekiConfig.load(root);
  final result = await KarekiRunner().run(
    RunRequest(rootPath: root, config: config),
  );

  final reporter = TextReporter();
  // ignore: avoid_print
  print(reporter.render(result.findings, rootPath: root));
}
