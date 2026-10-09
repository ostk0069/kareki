import 'package:kareki/src/workspace/dart_source_files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  test(
    'includes scripts and source trees but prunes caches and build output',
    () {
      final workspace = TestWorkspace.create(
        'kareki_source_scope_',
        bootstrap: false,
      );
      addTearDown(workspace.dispose);
      const sources = [
        'script.dart',
        'lib/nested/api.dart',
        'bin/main.dart',
        'test/api_test.dart',
        'integration_test/app_test.dart',
        'example/main.dart',
        'tool/nested/helper.dart',
        'tools/helper.dart',
      ];
      for (final path in [
        ...sources,
        'README.md',
        'tool/README.md',
        'other/ignored.dart',
        '.dart_tool/generated.dart',
        'build/generated.dart',
        '.git/ignored.dart',
        'tool/.dart_tool/generated.dart',
        'tools/build/generated.dart',
        'lib/nested/.git/ignored.dart',
      ]) {
        workspace.write(path, '');
      }
      expect(
        packageDartFiles(
          workspace.path,
        ).map((file) => p.relative(file.path, from: workspace.path)),
        unorderedEquals(sources),
      );
    },
  );
}
