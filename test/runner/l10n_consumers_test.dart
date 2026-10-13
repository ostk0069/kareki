import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/l10n_workspace.dart';
import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_l10n_consumers_');
    writeL10n(workspace);
    final config = File(
      'test/fixtures/l10n_consumers/.dart_tool/package_config.json',
    );
    final payload =
        jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final packages = (payload['packages'] as List).cast<Map<String, dynamic>>();
    workspace.bootstrap = false;
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'runner_fixture',
            'rootUri': Uri.directory(workspace.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
          for (final package in packages)
            {
              ...package,
              'rootUri': config.absolute.uri
                  .resolve(package['rootUri'] as String)
                  .toString(),
            },
        ],
      }),
    );
  });
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze(String source) {
    workspace.write(
      'lib/main.dart',
      "import 'l10n/app_localizations.dart';\n$source",
    );
    return KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.defaults(),
        enabledRules: {RuleId.unusedL10n},
      ),
    );
  }

  test(
    'registered Mockito values, generated defaults and null matchers retain no keys',
    () async {
      final result = await analyze('''
import 'package:mockito/mockito.dart' as mock;
import 'package:matcher/expect.dart' as check;
class MockBag extends mock.Mock {
  AppLocalizations get l10n => super.noSuchMethod(Invocation.getter(#l10n),
      returnValue: AppLocalizations.of(Object()),
      returnValueForMissingStub: AppLocalizations.of(Object())) as AppLocalizations;
}
void main() {
  final bag = MockBag();
  final l10n = AppLocalizations.of(Object());
  mock.when(bag.l10n).thenReturn(l10n);
  check.expect(l10n, check.isNotNull);
  check.expect(l10n, check.isNull);
  print(bag.l10n.used);
}
''');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.single.stableId, endsWith('|l10n:dead'));
      expect(result.localizationUsage.single.used, 1);
      expect(result.localizationUsage.single.unused, 1);
      expect(result.localizationUsage.single.unknown, 0);
    },
  );

  for (final check in [
    'check.predicate((value) => true)',
    'check.isNotNull, formatter: (a, b, c, d, e) => "failure"',
  ]) {
    test('unmodeled matcher or formatter remains unknown: $check', () async {
      final result = await analyze('''
import 'package:matcher/expect.dart' as check;
void main() { check.expect(AppLocalizations.of(Object()), $check); }
''');
      expect(result.findings, isEmpty);
      expect(result.localizationUsage.single.unknown, 2);
    });
  }

  test(
    'localization returned inside escaping records remains unknown',
    () async {
      final result = await analyze('''
void main() {
  final value = AppLocalizations.of(Object());
  print((value, getter: () => value));
  print([(getter: () => value,)]);
}
''');
      expect(result.findings, isEmpty);
      expect(result.localizationUsage.single.unknown, 2);
    },
  );

  test('known uses stay used while remaining keys are unknown', () async {
    final result = await analyze('''
void main() {
  final value = AppLocalizations.of(Object());
  print(value.used);
  print(value);
}
''');
    expect(result.localizationUsage.single.used, 1);
    expect(result.localizationUsage.single.unknown, 1);
    expect(result.localizationUsage.single.unused, 0);
    expect(result.findings, isEmpty);
  });

  test(
    'record callback origins in a read-only final list are resolved',
    () async {
      final result = await analyze('''
void main() {
  final cases = [
    (run: (AppLocalizations value) => value.used),
    (run: (AppLocalizations value) => value.used),
  ];
  for (final item in cases) { print(item.run(AppLocalizations.of(Object()))); }
  final callback = (AppLocalizations value) => value.used;
  print(callback(AppLocalizations.of(Object())));
}
''');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.single.stableId, endsWith('|l10n:dead'));
    },
  );

  for (final extra in ['cases.add((run: supplied));', 'print(cases);']) {
    test('mutated or escaping callback lists remain unknown: $extra', () async {
      final result = await analyze('''
void main() {
  final cases = [(run: (AppLocalizations value) => value.used)];
  String Function(AppLocalizations) supplied = (value) => value.used;
  $extra
  for (final item in cases) { print(item.run(AppLocalizations.of(Object()))); }
}
''');
      expect(result.findings, isEmpty);
      expect(result.localizationUsage.single.used, 1);
      expect(result.localizationUsage.single.unknown, 1);
    });
  }

  test(
    'abstract dispatch with a known concrete local receiver is resolved',
    () async {
      final result = await analyze('''
abstract class Consumer { String read(AppLocalizations value); }
class Local extends Consumer { @override String read(AppLocalizations value) => value.used; }
void main() {
  final Consumer consumer = Local();
  print(consumer.read(AppLocalizations.of(Object())));
}
''');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.single.stableId, endsWith('|l10n:dead'));
    },
  );

  test(
    'available implementations do not close an unknown abstract receiver',
    () async {
      final result = await analyze('''
abstract class Consumer { String read(AppLocalizations value); }
class Local extends Consumer { @override String read(AppLocalizations value) => value.used; }
void invoke(Consumer consumer) { print(consumer.read(AppLocalizations.of(Object()))); }
void main() {}
''');
      expect(result.findings, isEmpty);
      expect(result.localizationUsage.single.unknown, 1);
    },
  );

  test(
    'parenthesized callbacks and literal record iteration are resolved',
    () async {
      final result = await analyze('''
void main() {
  final callback = ((AppLocalizations value) => value.used);
  print((callback)(AppLocalizations.of(Object())));
  for (final item in ([(run: (AppLocalizations value) => value.used)])) {
    print(item.run(AppLocalizations.of(Object())));
  }
  final dynamic record = (run: (AppLocalizations value) => value.used);
  print(record.run(AppLocalizations.of(Object())));
}
''');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings.single.stableId, endsWith('|l10n:dead'));
    },
  );

  test('a callback record escaping the loop is not a closed origin', () async {
    final result = await analyze('''
void main() {
  final cases = [(run: (AppLocalizations value) => value.used)];
  for (final item in cases) {
    print(item);
    print(item.run(AppLocalizations.of(Object())));
  }
}
''');
    expect(result.findings, isEmpty);
    expect(result.localizationUsage.single.unknown, 1);
  });

  test(
    'different concrete receiver implementations remain uncertain',
    () async {
      final result = await analyze('''
abstract class Consumer { String read(AppLocalizations value); }
class A extends Consumer { @override String read(AppLocalizations value) => value.used; }
class B extends Consumer { @override String read(AppLocalizations value) => value.used; }
void main() {
  final cases = [(consumer: A()), (consumer: B())];
  for (final item in cases) { print(item.consumer.read(AppLocalizations.of(Object()))); }
}
''');
      expect(result.findings, isEmpty);
      expect(result.localizationUsage.single.unknown, 1);
    },
  );

  test('same-name external APIs are not granted trusted contracts', () async {
    workspace.write('external/fake/pubspec.yaml', 'name: fake\n');
    workspace.write('external/fake/lib/fake.dart', '''
void expect(Object? value, Object? matcher) {}
Object get isNotNull => Object();
class PostExpectation { void thenReturn(Object? value) {} }
''');
    final config = File(
      p.join(workspace.path, '.dart_tool/package_config.json'),
    );
    final data = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    (data['packages'] as List).add({
      'name': 'fake',
      'rootUri': '../external/fake/',
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    });
    config.writeAsStringSync(jsonEncode(data));
    final result = await analyze('''
import 'package:fake/fake.dart' as fake;
void main() {
  final value = AppLocalizations.of(Object());
  fake.expect(value, fake.isNotNull);
  fake.PostExpectation().thenReturn(value);
}
''');
    expect(result.findings, isEmpty);
    expect(result.localizationUsage.single.unknown, 2);
  });

  test('changed Mockito sources invalidate the trusted contract', () async {
    final config = File(
      p.join(workspace.path, '.dart_tool/package_config.json'),
    );
    final data = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    final package = (data['packages'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((entry) => entry['name'] == 'mockito');
    final original = Directory.fromUri(Uri.parse(package['rootUri'] as String));
    final copy = Directory(p.join(workspace.path, 'external/mockito'))
      ..createSync(recursive: true);
    for (final file in Directory(
      p.join(original.path, 'lib'),
    ).listSync(recursive: true).whereType<File>()) {
      final target = File(
        p.join(copy.path, p.relative(file.path, from: original.path)),
      );
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
    final mock = File(p.join(copy.path, 'lib/src/mock.dart'));
    mock.writeAsStringSync(
      '${mock.readAsStringSync()}\n// Changed dependency implementation.\n',
    );
    package['rootUri'] = Uri.directory(copy.path).toString();
    config.writeAsStringSync(jsonEncode(data));
    final result = await analyze('''
import 'package:mockito/mockito.dart';
void main() { PostExpectation<AppLocalizations>().thenReturn(AppLocalizations.of(Object())); }
''');
    expect(result.findings, isEmpty);
    expect(result.localizationUsage.single.unknown, 2);
  });
}
