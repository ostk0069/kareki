import 'dart:convert';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  Future<RunResult> analyze({
    Set<String>? rules,
    Set<String>? packages,
    bool disregardIgnores = false,
  }) => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: rules ?? {RuleId.unusedElement, RuleId.testOnlyUsed},
      includePackages: packages,
      disregardFileLevelIgnores: disregardIgnores,
    ),
  );

  List<String> unused(RunResult result) => result.findings
      .where((f) => f.ruleId == RuleId.unusedElement)
      .map((f) => f.message)
      .toList();

  void mainBody(String body) => workspace.write(
    'bin/main.dart',
    "import 'package:app/api.dart';\nvoid main() { $body }\n",
  );

  setUp(() {
    workspace = TestWorkspace.create('kareki_enum_values_');
    workspace.writePubspec(name: 'app');
    workspace.write('lib/api.dart', 'enum Status { active, inactive }\n');
    mainBody('print(Status.active);');
  });
  tearDown(() => workspace.dispose());

  test(
    'reports only the unused value with precise location and JSON',
    () async {
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), ["Unused public enum value 'Status.inactive'."]);
      final finding = result.findings.single;
      expect(finding.line, 1);
      expect(finding.column, 23);
      expect(finding.length, 8);
      expect(finding.stableId, endsWith('|Status|inactive|enumConstant'));
      final json =
          jsonDecode(JsonReporter().render(result.findings))
              as Map<String, Object?>;
      final entry =
          (json['findings']! as List<Object?>).single! as Map<String, Object?>;
      expect(entry['ruleId'], 'unused_element');
    },
  );

  for (final body in [
    'print(Status.active); print(Status.inactive);',
    'Status value = .active; print(value); print(Status.inactive);',
    'print(Status.values);',
    "print(Status.values.byName('active'));",
    'print(Status.values.asNameMap());',
    'print(Status.values[0]);',
    'final all = Status.values; print(all.first);',
    'for (final value in Status.values) { print(value); }',
    'print(switch (Status.active) { Status.active => 1, Status.inactive => 2 });',
    'if (Status.active case Status.inactive) { print(1); }',
  ]) {
    test('keeps resolved values: $body', () async {
      mainBody(body);
      final result = await analyze();
      expect(result.analysisWarnings, isEmpty);
      expect(unused(result), isEmpty);
    });
  }

  test('type-only use does not keep constants alive', () async {
    mainBody('Status? value; print(value);');
    expect(
      unused(await analyze()),
      unorderedEquals([
        "Unused public enum value 'Status.active'.",
        "Unused public enum value 'Status.inactive'.",
      ]),
    );
  });

  test('dead direct and values references do not rescue values', () async {
    workspace.write('lib/api.dart', '''
enum Status { active, inactive }
void dead() { print(Status.inactive); print(Status.values); }
''');
    expect(
      unused(await analyze()),
      unorderedEquals([
        "Unused public enum value 'Status.inactive'.",
        "Unused public function 'dead'.",
      ]),
    );
  });

  test('same-named enums and unrelated values fields stay separate', () async {
    workspace.write('lib/other.dart', 'enum Status { active, inactive }\n');
    workspace.write('lib/api.dart', '''
export 'other.dart' hide Status;
enum Status { active, inactive }
class Other { static const values = [1, 2]; }
''');
    mainBody('print(Status.active); print(Other.values);');
    final result = await analyze();
    final values = result.findings.where(
      (f) => f.stableId.endsWith('enumConstant'),
    );
    expect(values, hasLength(3));
    expect(values.where((f) => f.filePath.endsWith('/api.dart')), hasLength(1));
  });

  test('private enums and private values are not reported', () async {
    workspace.write('lib/api.dart', '''
enum Status { active, _hidden }
enum _Private { active, inactive }
''');
    expect(unused(await analyze()), isEmpty);
  });

  test(
    'enhanced enum values retain constructors and argument dependencies',
    () async {
      workspace.write('lib/api.dart', '''
const usedCode = 1;
const deadCode = 2;
enum Status {
  active.named(usedCode), inactive.named(deadCode);
  const Status.named(this.code);
  final int code;
}
''');
      mainBody('print(Status.active.code);');
      expect(
        unused(await analyze()),
        unorderedEquals([
          "Unused public enum value 'Status.inactive'.",
          "Unused public topLevelVariable 'deadCode'.",
        ]),
      );
    },
  );

  test('part and prefixed re-export references resolve exactly', () async {
    workspace.write('lib/api.dart', "export 'types.dart';\n");
    workspace.write('lib/types.dart', "part 'status.dart';\n");
    workspace.write(
      'lib/status.dart',
      "part of 'types.dart';\nenum Status { active, inactive }\n",
    );
    workspace.write(
      'bin/main.dart',
      "import 'package:app/api.dart' as api;\nvoid main() => print(api.Status.active);\n",
    );
    expect(unused(await analyze()), [
      "Unused public enum value 'Status.inactive'.",
    ]);
  });

  test('test-only values are reported separately from unused values', () async {
    workspace.write('lib/api.dart', 'enum Status { active, tested, unused }\n');
    workspace.write(
      'test/status_test.dart',
      "import 'package:app/api.dart';\nvoid main() => print(Status.tested);\n",
    );
    final result = await analyze();
    expect(unused(result), ["Unused public enum value 'Status.unused'."]);
    expect(
      result.findings
          .where((f) => f.ruleId == RuleId.testOnlyUsed)
          .map((f) => f.message),
      ["Public enum value 'Status.tested' is only referenced from test code."],
    );
  });

  test('generated sources retain the exact values they reference', () async {
    workspace.write(
      'lib/use.g.dart',
      "import 'api.dart';\nvoid generated() => print(Status.inactive);\n",
    );
    expect(unused(await analyze()), isEmpty);
  });

  test('keep-alive annotations on an enum protect its values', () async {
    workspace.write(
      'kareki-config.yaml',
      'keep_alive_annotations:\n  custom:\n    - _Keep\n',
    );
    workspace.write('lib/api.dart', '''
class _Keep { const _Keep(); }
@_Keep()
enum Status { active, inactive }
''');
    expect(unused(await analyze()), isEmpty);
  });

  test('value annotation does not keep sibling values alive', () async {
    workspace.write(
      'kareki-config.yaml',
      'keep_alive_annotations:\n  custom:\n    - _Keep\n',
    );
    workspace.write('lib/api.dart', '''
class _Keep { const _Keep(); }
enum Status { @_Keep() active, inactive }
''');
    mainBody('Status? value; print(value);');
    expect(unused(await analyze()), [
      "Unused public enum value 'Status.inactive'.",
    ]);
  });

  for (final directive in [
    '// kareki: ignore_for_file=unused_element',
    '// kareki: ignore_for_file=inactive',
  ]) {
    test('file suppression: $directive', () async {
      workspace.write(
        'lib/api.dart',
        '$directive\nenum Status { active, inactive }\n',
      );
      expect(unused(await analyze()), isEmpty);
      expect(unused(await analyze(disregardIgnores: true)), [
        "Unused public enum value 'Status.inactive'.",
      ]);
    });
  }

  test('line suppression and name exclusions apply to values', () async {
    workspace.write('lib/api.dart', '''
enum Status {
  active,
  // kareki: ignore=unused_element
  ignored,
  excluded,
  inactive,
}
''');
    workspace.write(
      'kareki-config.yaml',
      'exclude:\n  names:\n    - excluded\n',
    );
    expect(unused(await analyze()), [
      "Unused public enum value 'Status.inactive'.",
    ]);
  });

  test('disabling the rule disables enum value findings', () async {
    expect((await analyze(rules: {RuleId.unusedFile})).findings, isEmpty);
    workspace.write(
      'kareki-config.yaml',
      'ignore:\n  rules:\n    - unused_element\n',
    );
    expect((await analyze()).findings, isEmpty);
  });

  test('stable IDs survive line shifts and baseline serialization', () async {
    final original = (await analyze()).findings;
    final baselinePath = '${workspace.path}/baseline.json';
    Baseline.write(baselinePath, original, rootPath: workspace.path);
    workspace.write(
      'lib/api.dart',
      '\n\n// moved\nenum Status { active, inactive }\n',
    );
    final moved = (await analyze()).findings.single;
    expect(moved.line, 4);
    expect(moved.stableId, original.single.stableId);
    expect(
      Baseline.load(baselinePath)!.contains(moved, rootPath: workspace.path),
      isTrue,
    );
  });

  test('cross-package references survive reporting filters', () async {
    workspace.write('pubspec.yaml', '''
name: root
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - app
  - models
''');
    workspace.write(
      'models/pubspec.yaml',
      'name: models\nresolution: workspace\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\n',
    );
    workspace.write(
      'app/pubspec.yaml',
      'name: app\nresolution: workspace\nenvironment:\n  sdk: ">=3.10.0 <4.0.0"\ndependencies:\n  models: any\n',
    );
    workspace.write(
      'models/lib/api.dart',
      'enum Status { active, inactive }\n',
    );
    workspace.write(
      'app/bin/main.dart',
      "import 'package:models/api.dart';\nvoid main() => print(Status.active);\n",
    );
    workspace.write('lib/api.dart', '');
    workspace.write('bin/main.dart', 'void main() {}\n');
    final result = await analyze(packages: {'models'});
    expect(unused(result), ["Unused public enum value 'Status.inactive'."]);
    expect(result.findings.single.packageName, 'models');
  });

  test('doctor distinguishes effective and stale value suppressions', () async {
    workspace.write('lib/api.dart', '''
enum Status {
  // kareki: ignore=unused_element
  active,
  // kareki: ignore=inactive
  inactive,
}
''');
    final result = await DoctorRunner().analyze(
      DoctorRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );
    expect(result.analysisWarnings, isEmpty);
    expect(result.findings, hasLength(1));
    expect(result.findings.single.subject, 'lib/api.dart:3');
    expect(result.findings.single.detail, contains('unused_element'));
  });

  test('values used only by tests retain all values as test-only', () async {
    workspace.write('bin/main.dart', 'void main() {}\n');
    workspace.write(
      'test/status_test.dart',
      "import 'package:app/api.dart';\nvoid main() => print(Status.values);\n",
    );
    final result = await analyze();
    expect(unused(result), isEmpty);
    expect(
      result.findings.where((f) => f.stableId.endsWith('enumConstant')),
      hasLength(2),
    );
    expect(
      result.findings.every((f) => f.ruleId == RuleId.testOnlyUsed),
      isTrue,
    );
  });

  test(
    'unused enums and values follow the existing member reporting policy',
    () async {
      workspace.write('bin/main.dart', 'void main() {}\n');
      expect(
        unused(await analyze()),
        unorderedEquals([
          "Unused public enumDecl 'Status'.",
          "Unused public enum value 'Status.active'.",
          "Unused public enum value 'Status.inactive'.",
        ]),
      );
    },
  );

  for (final source in [
    'enum Status { active, inactive',
    "import 'package:missing/missing.dart';\nenum Status { active, inactive }",
  ]) {
    test(
      'invalid input fails analysis without emitting findings: $source',
      () async {
        workspace.write('lib/api.dart', source);
        await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      },
    );
  }
}
