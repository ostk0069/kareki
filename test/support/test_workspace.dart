import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

String fixturePath(String name) {
  final root = p.join(Directory.current.path, 'test', 'fixtures', name);
  configureTestPackages(root);
  return root;
}

/// Bootstrap synthetic test packages without fetching their deliberately fake
/// dependency declarations. Imports resolve to real installed test dependencies
/// or to the explicitly scaffolded local packages, never to production stubs.
void configureTestPackages(String root) {
  final ownConfig = File(
    p.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  );
  final entries = <String, Map<String, Object?>>{};
  final installed =
      jsonDecode(ownConfig.readAsStringSync()) as Map<String, dynamic>;
  for (final entry
      in (installed['packages'] as List).cast<Map<String, dynamic>>()) {
    entries[entry['name'] as String] = {
      ...entry,
      'rootUri': ownConfig.uri.resolve(entry['rootUri'] as String).toString(),
    };
  }
  for (final file in Directory(
    root,
  ).listSync(recursive: true).whereType<File>()) {
    if (p.basename(file.path) != 'pubspec.yaml') continue;
    final name = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(file.readAsStringSync())?.group(1);
    if (name == null) continue;
    entries[name] = {
      'name': name,
      'rootUri': Uri.directory(p.dirname(file.absolute.path)).toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    };
  }
  final target = File(p.join(root, '.dart_tool', 'package_config.json'));
  final contents = jsonEncode({
    'configVersion': 2,
    'packages': entries.values.toList(),
  });
  if (target.existsSync() && target.readAsStringSync() == contents) return;
  target.parent.createSync(recursive: true);
  final temporary = target.parent.createTempSync('kareki_package_config_');
  try {
    File(p.join(temporary.path, 'package_config.json'))
      ..writeAsStringSync(contents)
      ..renameSync(target.path);
  } finally {
    temporary.deleteSync(recursive: true);
  }
}

/// Disposable on-disk workspace for runner integration tests.
class TestWorkspace {
  TestWorkspace._(this.directory);

  factory TestWorkspace.create(String prefix, {bool bootstrap = true}) =>
      TestWorkspace._(Directory.systemTemp.createTempSync(prefix))
        ..bootstrap = bootstrap;

  final Directory directory;
  bool bootstrap = true;

  String get path => directory.path;

  void write(String relativePath, String contents) {
    final file = File(p.join(path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    if (bootstrap && p.basename(relativePath) == 'pubspec.yaml') {
      configureTestPackages(path);
    }
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
