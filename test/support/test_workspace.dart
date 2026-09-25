import 'dart:io';

import 'package:path/path.dart' as p;

String fixturePath(String name) =>
    p.join(Directory.current.path, 'test', 'fixtures', name);

/// Disposable on-disk workspace for runner integration tests.
class TestWorkspace {
  TestWorkspace._(this.directory);

  factory TestWorkspace.create(String prefix) =>
      TestWorkspace._(Directory.systemTemp.createTempSync(prefix));

  final Directory directory;

  String get path => directory.path;

  void write(String relativePath, String contents) {
    final file = File(p.join(path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  void writePubspec({
    String name = 'runner_fixture',
    Set<String> dependencies = const {},
    Set<String> devDependencies = const {},
  }) {
    final dependencySection = _dependencySection('dependencies', dependencies);
    final devDependencySection = _dependencySection(
      'dev_dependencies',
      devDependencies,
    );
    write('pubspec.yaml', '''
name: $name
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
$dependencySection$devDependencySection''');
  }

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  String _dependencySection(String heading, Set<String> dependencies) {
    if (dependencies.isEmpty) return '';
    final entries = dependencies.toList()..sort();
    return '$heading:\n${entries.map((name) => '  $name: any').join('\n')}\n';
  }
}
