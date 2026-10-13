import 'dart:convert';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  Future<RunResult> analyze({Set<String>? rules}) => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: rules ?? {RuleId.unusedElement, RuleId.testOnlyUsed},
    ),
  );

  List<String> unused(RunResult result) => result.findings
      .where((finding) => finding.ruleId == RuleId.unusedElement)
      .map((finding) => finding.message)
      .toList();

  void mainBody(String body) => workspace.write(
    'bin/main.dart',
    "import 'package:app/api.dart';\nvoid main() { $body }\n",
  );

  setUp(() {
    workspace = TestWorkspace.create('kareki_private_');
    workspace.writePubspec(name: 'app');
    workspace.write('lib/api.dart', 'void run() {}');
    mainBody('run();');
  });
  tearDown(() => workspace.dispose());

  test(
    'reports private top-level declarations and precise locations',
    () async {
      workspace.write('lib/api.dart', '''
void run() {}
class _Class {}
mixin _Mixin {}
enum _Enum { value }
typedef _Alias = int;
void _function() {}
int _variable = 0;
int get _getter => 0;
set _setter(int value) {}
extension _Extension on int { int twice() => this * 2; }
extension type _Wrapper(int value) {}
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(
        unused(result),
        unorderedEquals([
          "Unused private classDecl '_Class'.",
          "Unused private mixinDecl '_Mixin'.",
          "Unused private enumDecl '_Enum'.",
          "Unused private enum value '_Enum.value'.",
          "Unused private typedefDecl '_Alias'.",
          "Unused private function '_function'.",
          "Unused private topLevelVariable '_variable'.",
          "Unused private getter '_getter'.",
          "Unused private setter '_setter'.",
          "Unused private extensionDecl '_Extension'.",
          "Unused private method '_Extension.twice'.",
          "Unused private extensionDecl '_Wrapper'.",
        ]),
      );
      final finding = result.findings.singleWhere(
        (finding) => finding.message.contains("'_function'"),
      );
      expect(finding.line, 6);
      expect(finding.column, 6);
      expect(finding.length, 9);
      expect(finding.stableId, endsWith('||_function|function'));
      final json =
          jsonDecode(JsonReporter().render([finding])) as Map<String, dynamic>;
      final entry = (json['findings'] as List).single as Map<String, dynamic>;
      expect(entry['ruleId'], 'unused_element');
    },
  );

  test('used private types retain calls but not unrelated members', () async {
    workspace.write('lib/api.dart', '''
void run() => _Class().used();
class _Class {
  _Class();
  _Class._dead();
  void used() => _helper();
  void dead() {}
  int _field = 0;
  int get _getter => 0;
  set _setter(int value) {}
}
void _helper() {}
''');
    final result = await analyze();
    expect(result.analysisWarnings, isEmpty);
    expect(
      unused(result),
      unorderedEquals([
        "Unused private constructor '_Class._dead'.",
        "Unused private method '_Class.dead'.",
        "Unused private field '_Class._field'.",
        "Unused private getter '_Class._getter'.",
        "Unused private setter '_Class._setter'.",
      ]),
    );
  });

  test('private members of a public type are checked independently', () async {
    workspace.write('lib/api.dart', '''
void run() => Public().used();
class Public {
  void used() => _used();
  void _used() {}
  void _dead() {}
  Public();
  Public._dead();
}
''');
    expect(
      unused(await analyze()),
      unorderedEquals([
        "Unused private method 'Public._dead'.",
        "Unused private constructor 'Public._dead'.",
      ]),
    );
  });

  test(
    'dead references and private cycles do not retain declarations',
    () async {
      workspace.write('lib/api.dart', '''
void run() {}
void dead() => _helper();
void _helper() {}
void _first() => _second();
void _second() => _first();
''');
      expect(
        unused(await analyze()),
        unorderedEquals([
          "Unused public function 'dead'.",
          "Unused private function '_helper'.",
          "Unused private function '_first'.",
          "Unused private function '_second'.",
        ]),
      );
    },
  );

  for (final path in ['bin/main.dart', 'tool/run.dart', 'test/run_test.dart']) {
    test(
      '$path does not root dead private declarations or their bodies',
      () async {
        workspace.write(path, '''
void main() => _used();
void _used() => _Alive().used();
class _Alive {
  void used() {}
  void dead() {}
}
void _dead() => _dependency();
void _dependency() {}
''');
        final messages = unused(await analyze());
        expect(
          messages,
          containsAll([
            "Unused private method '_Alive.dead'.",
            "Unused private function '_dead'.",
            "Unused private function '_dependency'.",
          ]),
        );
        expect(messages.any((message) => message.contains("'_used'")), isFalse);
        expect(
          messages.any((message) => message.contains("'_Alive.used'")),
          isFalse,
        );
      },
    );
  }

  test(
    'parts share private identities but separate libraries do not',
    () async {
      workspace.write('lib/api.dart', '''
part 'impl.dart';
void run() => _helper();
''');
      workspace.write(
        'lib/impl.dart',
        "part of 'api.dart';\nvoid _helper() {}\n",
      );
      workspace.write('lib/other.dart', 'void _helper() {}');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), ["Unused private function '_helper'."]);
      expect(result.findings.single.filePath, endsWith('/lib/other.dart'));
    },
  );

  test(
    'dynamic private targets are retained only within their library',
    () async {
      workspace.write('lib/api.dart', '''
part 'impl.dart';
void run() { dynamic value = _Candidate(); value._method(); }
''');
      workspace.write('lib/impl.dart', '''
part of 'api.dart';
class _Candidate { void _method() {} }
''');
      workspace.write('lib/other.dart', 'class _Other { void _method() {} }');
      final result = await analyze();
      expect(
        unused(result),
        unorderedEquals([
          "Unused private classDecl '_Other'.",
          "Unused private method '_Other._method'.",
        ]),
      );
      expect(result.analysisWarnings, hasLength(1));
      expect(result.analysisWarnings.single, contains('impl.dart'));
      expect(result.analysisWarnings.single, isNot(contains('other.dart')));
    },
  );

  test(
    'constructors, accessors, tear-offs and initializers retain dependencies',
    () async {
      workspace.write('lib/api.dart', '''
void run() {
  final value = _Class._factory();
  value._value = 1;
  print(value._value);
  final callback = value._method;
  callback();
}
int _initialize() => 0;
class _Class {
  factory _Class._factory() = _Class._actual;
  _Class._actual();
  int _backing = _initialize();
  int get _value => _backing;
  set _value(int value) { _backing = value; }
  void _method() {}
}
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), isEmpty);
    },
  );

  test(
    'same-library private overrides and runtime hooks are retained',
    () async {
      workspace.write('lib/api.dart', '''
abstract class _Base {
  void _method();
  int get value;
  set value(int input);
}
class _Impl extends _Base {
  @override
  void _method() {}
  @override
  int get value => 0;
  @override
  set value(int input) {}
  @override
  String toString() => 'impl';
  void call() {}
  Map<String, Object?> toJson() => {};
}
void run() => print(_Impl());
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), isEmpty);
    },
  );

  test(
    'explicit entry files and generated files retain private declarations',
    () async {
      workspace.write(
        'kareki-config.yaml',
        'entry_points:\n  files: [lib/api.dart]\n',
      );
      workspace.write(
        'lib/api.dart',
        'void _explicit() => _helper();\nvoid _helper() {}',
      );
      workspace.write('bin/main.dart', 'void main() {}');
      workspace.write('lib/use.g.dart', '''
part of 'shared.dart';
void _generated() => _used();
''');
      workspace.write('lib/shared.dart', '''
part 'use.g.dart';
void _used() {}
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), isEmpty);
    },
  );

  test(
    'keep-alive annotations and explicit names retain private helpers',
    () async {
      workspace.write('kareki-config.yaml', '''
entry_points:
  names: [_named]
keep_alive_annotations:
  custom: [_Keep]
''');
      workspace.write('lib/api.dart', '''
class _Keep { const _Keep(); }
@_Keep()
void _annotated() => _dependency();
void _named() => _dependency();
void _dependency() {}
void run() {}
''');
      expect(unused(await analyze()), isEmpty);
    },
  );

  test(
    'private test-only helpers are alive without public test-only findings',
    () async {
      workspace.write('lib/api.dart', '''
void run() {}
void tested() => _helper();
void _helper() => _Private().method();
class _Private { void method() {} }
''');
      workspace.write('test/api_test.dart', '''
import 'package:app/api.dart';
void main() => tested();
''');
      final result = await analyze();
      expect(unused(result), isEmpty);
      expect(
        result.findings.single.message,
        "Public function 'tested' is only referenced from test code.",
      );
    },
  );

  test(
    'suppression, name exclusions, baseline and doctor recognize private findings',
    () async {
      workspace.write('kareki-config.yaml', 'exclude:\n  names: [_excluded]\n');
      workspace.write('lib/api.dart', '''
void run() {}
// kareki: ignore=unused_element
void _suppressed() {}
void _excluded() {}
void _dead() {}
''');
      final result = await analyze();
      expect(unused(result), ["Unused private function '_dead'."]);
      final baseline = Baseline.fromFindings(
        result.findings,
        rootPath: workspace.path,
      );
      expect(
        baseline.contains(result.findings.single, rootPath: workspace.path),
        isTrue,
      );
      workspace.write('lib/api.dart', '''
void run() {}
// kareki: ignore=unused_element
void _suppressed() {}
void _excluded() {}

void _dead() {}
''');
      expect(
        baseline.contains(
          (await analyze()).findings.single,
          rootPath: workspace.path,
        ),
        isTrue,
      );
      final doctor = await DoctorRunner().analyze(
        DoctorRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
        ),
      );
      expect(doctor.findings, isEmpty);
      expect((await analyze(rules: {RuleId.testOnlyUsed})).findings, isEmpty);
    },
  );

  test(
    'file-level ignores and rule disabling apply to private findings',
    () async {
      workspace.write('lib/api.dart', '''
// kareki: ignore_for_file=unused_element
void run() {}
void _dead() {}
''');
      expect(unused(await analyze()), isEmpty);
      workspace.write(
        'kareki-config.yaml',
        'ignore:\n  rules: [unused_element]\n',
      );
      workspace.write('lib/api.dart', 'void run() {}\nvoid _dead() {}');
      expect((await analyze()).findings, isEmpty);
    },
  );

  test(
    'private enum values and language declarations retain exact uses',
    () async {
      workspace.write('lib/api.dart', '''
enum _Status { used, dead }
mixin _Mixin { int value() => 1; }
class _Host with _Mixin {}
typedef _Alias = _Host;
extension _Extension on int { int twice() => this * 2; }
extension type _Wrapper(int value) {}
void run() {
  _Alias host = _Host();
  print(host.value());
  print(_Status.used);
  print(_Extension(1).twice());
  print(_Wrapper(1).value);
}
''');
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), ["Unused private enum value '_Status.dead'."]);
    },
  );

  test('private primary constructor fields use resolved identities', () async {
    if (!supportsPrimaryConstructors) return;
    workspace.write('lib/api.dart', '''
class _Point(final int _used, final int _dead) {
  int value() => _used;
}
void run() => print(_Point(1, 2).value());
''');
    configureTestPackages(workspace.path, languageVersion: testLanguageVersion);
    final result = await analyze();
    expect(result.analysisWarnings, isEmpty);
    expect(unused(result), ["Unused private field '_Point._dead'."]);
  });
}
