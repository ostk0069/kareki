import 'dart:io';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void _write(String root, String path, String contents) {
  final file = File(p.join(root, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writePubspec(
  String root, {
  String dependencies = '',
  String devDependencies = '',
}) {
  _write(root, 'pubspec.yaml', '''
name: resilience_fixture
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
$dependencies$devDependencies''');
}

RunResult _run(
  String root, {
  Set<String>? enabledRules,
  bool strictDependencies = false,
}) => KarekiRunner().run(
  RunRequest(
    rootPath: root,
    config: KarekiConfig.load(root),
    enabledRules: enabledRules,
    strictDependencies: strictDependencies,
  ),
);

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('kareki_resilience_');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test('conditional directives and parts do not produce false positives', () {
    _writePubspec(
      workspace.path,
      dependencies: '''
dependencies:
  collection: any
  meta: any
''',
    );
    _write(workspace.path, 'lib/api.dart', '''
import 'stub.dart' if (dart.library.html) 'browser.dart';
export 'package:meta/meta.dart'
    if (dart.library.io) 'package:collection/collection.dart';
part 'src/api_part.dart';

String platformName() => platformNameImpl;
''');
    _write(workspace.path, 'lib/stub.dart', '''
const platformNameImpl = 'stub';
''');
    _write(workspace.path, 'lib/browser.dart', '''
const platformNameImpl = 'browser';
''');
    _write(workspace.path, 'lib/src/api_part.dart', '''
part of '../api.dart';

String partValue() => 'part';
''');
    _write(workspace.path, 'bin/main.dart', '''
import 'package:resilience_fixture/api.dart';

void main() => print(platformName());
''');

    final result = _run(workspace.path);
    final unusedFiles = result.findings
        .where((finding) => finding.ruleId == RuleId.unusedFile)
        .map((finding) => p.basename(finding.filePath));

    expect(unusedFiles, isNot(contains('stub.dart')));
    expect(unusedFiles, isNot(contains('browser.dart')));
    expect(unusedFiles, isNot(contains('api_part.dart')));
    expect(
      result.findings
          .where((finding) => finding.ruleId == RuleId.unusedPubDependency)
          .map((finding) => finding.message),
      isEmpty,
    );
  });

  test('excluded generated code keeps the APIs it references alive', () {
    _writePubspec(workspace.path);
    _write(workspace.path, 'lib/api.dart', '''
class KeptByGenerated {}
class TrulyUnused {}

void configure({String? token}) => print(token);
''');
    _write(workspace.path, 'lib/model.g.dart', '''
import 'api.dart';

KeptByGenerated createModel() => KeptByGenerated();
void configureGeneratedModel() => configure(token: 'generated');
''');
    _write(workspace.path, 'bin/main.dart', 'void main() {}\n');

    final result = _run(workspace.path);

    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'KeptByGenerated'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'TrulyUnused'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'token'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedFile &&
            finding.filePath.endsWith('model.g.dart'),
      ),
      isFalse,
    );
  });

  test('an incomplete source file does not hide findings in valid files', () {
    _writePubspec(workspace.path);
    _write(workspace.path, 'lib/broken.dart', '''
class Broken {
  void unfinished(
''');
    _write(workspace.path, 'lib/api.dart', 'class KnownUnused {}\n');
    _write(workspace.path, 'bin/main.dart', 'void main() {}\n');

    final result = _run(workspace.path);

    expect(result.filesAnalyzed, 3);
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'KnownUnused'"),
      ),
      isTrue,
    );
  });

  test('strict dependency mode adds unused dev dependencies only', () {
    _writePubspec(
      workspace.path,
      dependencies: '''
dependencies:
  collection: any
''',
      devDependencies: '''
dev_dependencies:
  test: any
''',
    );
    _write(workspace.path, 'bin/main.dart', 'void main() {}\n');

    final defaultResult = _run(
      workspace.path,
      enabledRules: {RuleId.unusedPubDependency},
    );
    final strictResult = _run(
      workspace.path,
      enabledRules: {RuleId.unusedPubDependency},
      strictDependencies: true,
    );

    expect(
      defaultResult.findings.map((finding) => finding.message),
      contains(contains("Dependency 'collection'")),
    );
    expect(
      defaultResult.findings.map((finding) => finding.message),
      isNot(contains(contains("Dependency 'test'"))),
    );
    expect(
      strictResult.findings.map((finding) => finding.message),
      containsAll(<dynamic>[
        contains("Dependency 'collection'"),
        contains("Dependency 'test'"),
      ]),
    );
  });
}
