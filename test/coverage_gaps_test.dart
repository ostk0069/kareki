import 'dart:convert';
import 'dart:io';

import 'package:kareki/src/baseline/baseline.dart';
import 'package:kareki/src/cli/cli.dart';
import 'package:kareki/src/cli/doctor_cli.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/dependency/pub_dependency_checker.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/doctor/doctor_reporter.dart';
import 'package:kareki/src/doctor/doctor_runner.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:kareki/src/preset/preset.dart';
import 'package:kareki/src/preset/preset_registry.dart';
import 'package:kareki/src/reporter/reporter.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('kareki_coverage_');
    File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: coverage_app
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
''');
    Directory(p.join(tempRoot.path, 'lib')).createSync();
    File(
      p.join(tempRoot.path, 'lib', 'main.dart'),
    ).writeAsStringSync('void main() {}\n');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  group('CLI branches', () {
    test('main CLI handles help and malformed arguments', () {
      expect(runCli(['--help'], workingDirectory: tempRoot.path), 0);
      expect(runCli(['--not-an-option'], workingDirectory: tempRoot.path), 64);
    });

    test('main CLI handles formats, rules, packages, and strict mode', () {
      expect(
        runCli([
          '--format',
          'json',
          '--packages',
          'coverage_app',
          '--rule',
          RuleId.unusedElement,
          '--strict',
        ], workingDirectory: tempRoot.path),
        anyOf(0, 1),
      );
      expect(
        runCli(['--rule', 'not_a_rule'], workingDirectory: tempRoot.path),
        64,
      );
    });

    test('main CLI reports a malformed baseline', () {
      final baseline = p.join(tempRoot.path, 'baseline.json');
      File(baseline).writeAsStringSync('[]');
      expect(
        runCli(['--baseline', baseline], workingDirectory: tempRoot.path),
        64,
      );
    });

    test('main CLI keeps findings absent from a partial baseline', () {
      File(
        p.join(tempRoot.path, 'lib', 'dead.dart'),
      ).writeAsStringSync('class Dead {}\nclass AlsoDead {}\n');
      final config = KarekiConfig.load(tempRoot.path);
      final findings = KarekiRunner()
          .run(RunRequest(rootPath: tempRoot.path, config: config))
          .findings;
      final baseline = p.join(tempRoot.path, 'baseline.json');
      Baseline.write(baseline, [findings.first], rootPath: tempRoot.path);

      expect(
        runCli(['--baseline', baseline], workingDirectory: tempRoot.path),
        1,
      );
    });

    test('doctor dispatch handles help, malformed options, text, and json', () {
      expect(runCli(['doctor', '--help'], workingDirectory: tempRoot.path), 0);
      expect(
        runDoctor(['--not-an-option'], workingDirectory: tempRoot.path),
        64,
      );
      expect(runDoctor([], workingDirectory: tempRoot.path), 0);

      File(p.join(tempRoot.path, 'kareki-config.yaml')).writeAsStringSync('''
version: 1
ignore:
  packages: [missing]
''');
      expect(
        runDoctor(['--format', 'json'], workingDirectory: tempRoot.path),
        1,
      );
    });
  });

  test('reporters render empty, detailed, relative, and JSON output', () {
    final doctorFindings = [
      DoctorFinding(
        kind: DoctorIssueKind.unusedExclude,
        subject: '**/*.old.dart',
        detail: 'exclude.files',
      ),
      DoctorFinding(kind: DoctorIssueKind.unusedIgnorePackage, subject: 'gone'),
    ];
    expect(TextDoctorReporter().render(const []), contains('healthy'));
    expect(TextDoctorReporter().render(doctorFindings), contains('2 issue'));
    final doctorJson = jsonDecode(JsonDoctorReporter().render(doctorFindings));
    expect((doctorJson as Map)['findings'], hasLength(2));

    final findings = [
      Finding(
        ruleId: RuleId.unusedElement,
        severity: Severity.warning,
        message: 'Unused A',
        packageName: 'z_pkg',
        filePath: p.join(tempRoot.path, 'lib', 'z.dart'),
        line: 2,
        column: 3,
        length: 1,
        stableId: 'z',
      ),
      Finding(
        ruleId: RuleId.unusedFile,
        severity: Severity.info,
        message: 'Unused file',
        packageName: 'a_pkg',
        filePath: p.join(tempRoot.path, 'lib', 'a.dart'),
        line: 1,
        column: 1,
        length: 0,
        stableId: 'a',
      ),
    ];
    expect(TextReporter().render(const []), contains('no unused'));
    expect(
      TextReporter().render(findings, rootPath: tempRoot.path),
      allOf(contains('a_pkg'), contains(p.join('lib', 'a.dart'))),
    );
    expect(TextReporter().render(findings), contains(tempRoot.path));
    final json =
        jsonDecode(JsonReporter().render(findings, rootPath: tempRoot.path))
            as Map<String, dynamic>;
    expect(json['findings'], hasLength(2));
    expect(JsonReporter().render(findings), contains(tempRoot.path));
  });

  test('config parses custom values and supporting value objects', () {
    File(p.join(tempRoot.path, 'kareki-config.yaml')).writeAsStringSync('''
version: 1
packages:
  include: ['.']
entry_points:
  files: ['tool/**']
keep_alive_annotations:
  presets: [freezed]
custom_presets:
  custom:
    keep_alive_annotations: [Keep]
    annotation_implied_packages:
      Keep: [one]
  ignored: invalid
annotation_implied_packages:
  Keep: [two]
sdk_packages: [dart_sdk]
output:
  format: json
''');
    final config = KarekiConfig.load(tempRoot.path);
    expect(config.entryPointFiles, ['tool/**']);
    expect(config.enabledPresetNames, {'freezed'});
    expect(config.customPresets.single.name, 'custom');
    expect(config.sdkPackages, {'dart_sdk'});
    expect(config.output, OutputFormat.json);

    final registry = PresetRegistry(
      enabledPresetNames: {'freezed'},
      customPresets: const [
        Preset(
          name: 'custom',
          keepAliveAnnotations: {'Keep'},
          annotationImpliedPackages: {
            'Keep': {'one'},
          },
        ),
        Preset(
          name: 'custom-two',
          annotationImpliedPackages: {
            'Keep': {'two'},
          },
        ),
      ],
    );
    expect(registry.keepAliveAnnotations, contains('Keep'));
    expect(registry.annotationImpliedPackages['Keep'], {'one', 'two'});

    final package = PackageInfo(
      name: 'app',
      rootPath: tempRoot.path,
      pubspecPath: p.join(tempRoot.path, 'pubspec.yaml'),
      dependencies: const {},
      devDependencies: const {},
    );
    expect(package.libPath, p.join(tempRoot.path, 'lib'));
    expect(package.testPath, p.join(tempRoot.path, 'test'));
    expect(package.binPath, p.join(tempRoot.path, 'bin'));

    File(p.join(tempRoot.path, 'pubspec.yaml')).writeAsStringSync('''
name: coverage_app
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
dependencies:
  one: any
  two: any
''');
    File(
      p.join(tempRoot.path, 'lib', 'main.dart'),
    ).writeAsStringSync('@Keep() class Kept {}\n');
    final dependencyFindings = KarekiRunner()
        .run(RunRequest(rootPath: tempRoot.path, config: config))
        .findings
        .where((finding) => finding.ruleId == RuleId.unusedPubDependency);
    expect(dependencyFindings, isEmpty);
  });

  test('baseline and doctor tolerate malformed baseline shapes', () {
    final baselinePath = p.join(tempRoot.path, 'baseline.json');
    File(baselinePath).writeAsStringSync('[]');
    expect(() => Baseline.load(baselinePath), throwsFormatException);

    File(p.join(tempRoot.path, 'kareki-config.yaml')).writeAsStringSync('''
version: 1
baseline: baseline.json
''');
    final result = DoctorRunner().run(
      DoctorRequest(
        rootPath: tempRoot.path,
        config: KarekiConfig.load(tempRoot.path),
      ),
    );
    expect(result.findings, isEmpty);
  });

  test('doctor sorts multiple findings and matches effective directives', () {
    File(p.join(tempRoot.path, 'kareki-config.yaml')).writeAsStringSync('''
version: 1
ignore:
  packages: [z_missing]
''');
    File(p.join(tempRoot.path, 'lib', 'dead.dart')).writeAsStringSync('''
// kareki: ignore_for_file=unused_element
class Dead {}
''');
    File(p.join(tempRoot.path, 'lib', 'stale.dart')).writeAsStringSync('''
// kareki: ignore_for_file=zzz, aaa
void used() {}
''');
    File(p.join(tempRoot.path, 'bin', 'main.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'package:coverage_app/stale.dart';
void main() => used();
''');

    final findings = DoctorRunner()
        .run(
          DoctorRequest(
            rootPath: tempRoot.path,
            config: KarekiConfig.load(tempRoot.path),
          ),
        )
        .findings;

    expect(
      findings.map((finding) => finding.detail),
      containsAll(['aaa', 'zzz']),
    );
    expect(
      findings.map((finding) => finding.kind),
      contains(DoctorIssueKind.unusedIgnorePackage),
    );
  });

  test('entry points include integration tests and annotated declarations', () {
    File(p.join(tempRoot.path, 'kareki-config.yaml')).writeAsStringSync('''
version: 1
keep_alive_annotations:
  custom: [Keep]
''');
    ParsedFile parse(String relativePath, String content) =>
        DeclarationCollector().collect(
          path: p.join(tempRoot.path, relativePath),
          packageName: 'coverage_app',
          content: content,
        );

    final integration = parse(
      'integration_test/scenario.dart',
      'class IntegrationScenario {}',
    );
    final annotated = parse('lib/kept.dart', '@Keep() class Kept {}');
    final config = KarekiConfig.load(tempRoot.path);
    final resolved =
        EntryPointResolver(
          config: config,
          presetRegistry: PresetRegistry(
            enabledPresetNames: config.enabledPresetNames,
            customPresets: config.customPresets,
          ),
        ).resolve(
          files: [integration, annotated],
          generatedFilePaths: const [],
          rootPath: tempRoot.path,
          packageRoots: {'coverage_app': tempRoot.path},
        );

    expect(resolved.testRootNames, contains('IntegrationScenario'));
    expect(resolved.productionRootNames, contains('Kept'));
  });

  test('dependency checker recognizes annotations and protobuf output', () {
    final parsed = DeclarationCollector().collect(
      path: p.join(tempRoot.path, 'lib', 'model.pb.dart'),
      packageName: 'coverage_app',
      content: "import 'dart:core';\n@Keep() class Model {}\n",
    );
    final package = PackageInfo(
      name: 'coverage_app',
      rootPath: tempRoot.path,
      pubspecPath: p.join(tempRoot.path, 'pubspec.yaml'),
      dependencies: const {'support', 'protobuf', 'fixnum'},
      devDependencies: const {},
    );

    final findings = PubDependencyChecker().check(
      package: package,
      filesInPackage: [parsed],
      annotationImpliedPackages: const {
        'Keep': {'support'},
      },
      sdkPackages: const {},
    );
    expect(findings, isEmpty);
  });

  test('collector covers declaration and invocation syntax variants', () {
    final parsed = DeclarationCollector().collect(
      path: p.join(tempRoot.path, 'lib', 'syntax.dart'),
      packageName: 'coverage_app',
      content: '''
class Base {
  const Base();
  Base.named({int? value});
}
mixin Mixed {
  void mixinMethod() {}
}
enum Choice {
  first.named(value: 1),
  second.new();
  const Choice.named({int? value});
}
extension NamedExtension on String {
  String extensionMethod() => this;
}
@prefix.Annotation.named()
class Annotated {}
typedef Modern = void Function(int value);
typedef Legacy(int value);

class Child extends Base {
  Child.named({int? value}) : super.named(value: value);
  Child.redirect({int? value}) : this.named(value: value);
}

void target({int? named}) {}
void calls(dynamic object, void Function({int? named}) callback) {
  target(named: 1);
  callback(named: 2);
  object.method(named: 3);
  object.property(named: 4);
  new Base.named(value: 5);
  (callback)(named: 6);
  (prefix.callback)(named: 7);
  (object?.callback)(named: 8);
  (callback ?? target)(named: 9);
}

const Base shorthand = .new();

void stub(int value) => throw new UnimplementedError();
''',
    );

    expect(
      parsed.declarations.map((declaration) => declaration.kind),
      containsAll([
        DeclarationKind.mixinDecl,
        DeclarationKind.enumDecl,
        DeclarationKind.extensionDecl,
        DeclarationKind.typedefDecl,
      ]),
    );
    expect(parsed.callSiteUsage, isNotEmpty);
  });
}
