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
        'hook/build.dart',
        'hook/link.dart',
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

  test(
    'nested pubspec boundaries also apply to source trees and ARB files',
    () {
      final workspace = TestWorkspace.create(
        'kareki_package_boundaries_',
        bootstrap: false,
      );
      addTearDown(workspace.dispose);
      workspace.write('pubspec.yaml', 'name: parent');
      workspace.write('lib/main.dart', '');
      workspace.write('lib/l10n/app_en.arb', '{}');
      workspace.write('example/pubspec.yaml', 'name: child');
      workspace.write('example/main.dart', '');
      workspace.write('example/lib/l10n/app_en.arb', '{}');
      workspace.write('tool/nested/pubspec.yaml', 'name: tooling');
      workspace.write('tool/nested/main.dart', '');
      expect(
        packageDartFiles(
          workspace.path,
        ).map((file) => p.relative(file.path, from: workspace.path)),
        ['lib/main.dart'],
      );
      expect(
        packageArbFiles(
          workspace.path,
        ).map((file) => p.relative(file.path, from: workspace.path)),
        ['lib/l10n/app_en.arb'],
      );
      expect(packageDartFiles(p.join(workspace.path, 'example')), hasLength(1));
    },
  );
}
