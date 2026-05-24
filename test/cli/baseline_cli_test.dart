import 'dart:io';

import 'package:kareki/src/cli/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String _fixture(String name) => p.join(
  Directory.current.path,
  'test',
  'fixtures',
  name,
);

void main() {
  group('CLI --write-baseline / --baseline', () {
    test(
      '--write-baseline writes a file containing the current findings, '
      'and a subsequent run with --baseline suppresses them (exit 0)',
      () {
        final root = _fixture('single_package');
        final tmp = Directory.systemTemp.createTempSync('kareki_cli_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final baselinePath = p.join(tmp.path, 'baseline.json');

        final writeCode = runCli(
          ['--root', root, '--baseline', baselinePath, '--write-baseline'],
          workingDirectory: root,
        );
        expect(writeCode, 0);
        expect(File(baselinePath).existsSync(), isTrue);
        final raw = File(baselinePath).readAsStringSync();
        expect(raw, contains('"tool": "kareki"'));
        expect(raw, contains('<root>/'));

        // Without baseline → findings exist → exit 1.
        final unsuppressedCode = runCli(
          ['--root', root],
          workingDirectory: root,
        );
        expect(unsuppressedCode, 1);

        // With baseline that captured every finding → exit 0.
        final suppressedCode = runCli(
          ['--root', root, '--baseline', baselinePath],
          workingDirectory: root,
        );
        expect(suppressedCode, 0);
      },
    );

    test(
      '--write-baseline without a configured path returns usage error 64',
      () {
        final root = _fixture('single_package');
        final code = runCli(
          ['--root', root, '--write-baseline'],
          workingDirectory: root,
        );
        expect(code, 64);
      },
    );
  });
}
