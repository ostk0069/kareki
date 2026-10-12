import 'package:kareki/kareki.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/l10n_workspace.dart';
import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() => workspace = TestWorkspace.create('kareki_l10n_'));
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze({Set<String>? packages, Set<String>? rules}) =>
      KarekiRunner().run(
        RunRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
          includePackages: packages,
          enabledRules: rules ?? {RuleId.unusedL10n},
        ),
      );

  Set<String> keys(RunResult result) => result.findings
      .where((f) => f.ruleId == RuleId.unusedL10n)
      .map((f) => f.stableId.split('|l10n:').last)
      .toSet();

  test(
    'getter references ignore generated roots, overrides and unrelated names',
    () async {
      writeL10n(workspace);
      workspace.write('lib/main.dart', '''
import 'l10n/app_localizations.dart';
class Unrelated { String get dead => 'not a translation'; }
void main() {
  print(AppLocalizations.of(Object()).used);
  print(Unrelated().dead);
  // AppLocalizations.of(context).dead
  print('l10n.dead');
}
''');
      final result = await analyze();
      expect(keys(result), {'dead'});
      expect(
        result.findings.single.filePath,
        p.join(workspace.path, 'lib/l10n/app_en.arb'),
      );
      expect(result.analysisWarnings, isEmpty);
    },
  );

  for (final use in [
    'void main() {}',
    'void main() { print(AppLocalizations.delegate); print(AppLocalizations.supportedLocales); }',
    'void main() { final value = AppLocalizations.of(Object()); print(value.runtimeType); }',
  ]) {
    test('import and infrastructure do not use keys: $use', () async {
      writeL10n(workspace);
      workspace.write(
        'lib/main.dart',
        "import 'l10n/app_localizations.dart';\n$use",
      );
      expect(keys(await analyze()), {'used', 'dead'});
    });
  }

  test('methods, named arguments, plural/select and tear-offs', () async {
    writeL10n(
      workspace,
      messages: {
        'hello': 'Hello {name}',
        'plural': '{n, plural, other{Items}}',
        'select': '{g, select, other{They}}',
        'dead': 'Dead',
      },
      methods: {
        'hello': 'String name',
        'plural': '{required int n}',
        'select': 'String g',
      },
    );
    workspace.write('lib/main.dart', '''
import 'l10n/app_localizations.dart';
void consume(String Function(String) callback) { print(callback('x')); }
void main() {
  final l10n = AppLocalizations.of(Object());
  consume(l10n.hello);
  print(l10n.plural(n: 2));
  print(l10n.select('other'));
}
''');
    expect(keys(await analyze()), {'dead'});
  });

  test(
    'wrappers, extensions, fields, arguments, aliases and exports',
    () async {
      writeL10n(workspace);
      workspace.write(
        'lib/facade.dart',
        "export 'l10n/app_localizations.dart';",
      );
      workspace.write('lib/main.dart', '''
import 'facade.dart' as loc;
loc.AppLocalizations useL10n() => loc.AppLocalizations.of(Object());
extension ContextL10n on Object { loc.AppLocalizations get l10n => useL10n(); }
class Holder {
  Holder(this.value);
  final loc.AppLocalizations value;
  String get text => value.used;
}
String read(loc.AppLocalizations value) => value.used;
void main() {
  print(Object().l10n.used);
  print(Holder(useL10n()).text);
  print(read(useL10n()));
}
''');
      final result = await analyze();
      expect(keys(result), {'dead'});
      expect(result.analysisWarnings, isEmpty);
    },
  );

  for (final path in [
    'test/use_test.dart',
    'integration_test/use_test.dart',
    'lib/unreachable.dart',
    'lib/code.g.dart',
  ]) {
    test(
      'reference source $path retains a key regardless of reachability',
      () async {
        writeL10n(workspace);
        workspace.write(path, '''
import 'package:runner_fixture/l10n/app_localizations.dart';
void neverCalled() { print(AppLocalizations.of(Object()).used); }
''');
        expect(keys(await analyze()), {'dead'});
      },
    );
  }

  test('direct locale implementation use maps back to the template', () async {
    writeL10n(workspace);
    workspace.write('lib/main.dart', '''
import 'l10n/app_localizations_en.dart';
void main() { print(AppLocalizationsEn().used); }
''');
    expect(keys(await analyze()), {'dead'});
  });

  test(
    'WINTICKET configuration and multiple locales report one template finding',
    () async {
      writeL10n(
        workspace,
        className: 'L10n',
        template: 'intl_messages_ja.arb',
        outputFile: 'l10n.dart',
      );
      workspace.write(
        'lib/l10n/intl_messages_en.arb',
        '{"@@locale":"en","used":"Used","dead":"Dead","extra":"Unused locale-only"}',
      );
      workspace.write('lib/main.dart', '''
import 'l10n/l10n.dart';
L10n useL10n() => L10n.of(Object());
void main() { print(useL10n().used); }
''');
      final result = await analyze();
      expect(keys(result), {'dead'});
      expect(result.findings, hasLength(1));
      expect(result.findings.single.filePath, endsWith('intl_messages_ja.arb'));
    },
  );

  test('custom paths, multi-dot output and implicit defaults', () async {
    writeL10n(
      workspace,
      arbDir: 'translations',
      outputDir: 'lib/generated',
      outputFile: 'strings.custom.dart',
      className: 'Strings',
      template: 'main_en.arb',
    );
    workspace.write(
      'lib/main.dart',
      "import 'generated/strings.custom.dart';\nvoid main() { print(Strings.of(Object()).used); }",
    );
    expect(keys(await analyze()), {'dead'});
    workspace.dispose();
    workspace = TestWorkspace.create('kareki_l10n_default_');
    writeL10n(workspace, configure: false);
    expect(keys(await analyze()), {'used', 'dead'});
  });

  test(
    'configured outputs outside ordinary source directories are resolved',
    () async {
      writeL10n(workspace, outputDir: 'generated/translations');
      workspace.write(
        'tool/main.dart',
        "import '../generated/translations/app_localizations.dart';\nvoid main() { print(AppLocalizations.of(Object()).used); }",
      );
      expect(keys(await analyze()), {'dead'});
      workspace.write('tool/main.dart', 'void main() {}');
      expect(keys(await analyze()), {'used', 'dead'});
    },
  );

  test('cross-package references and same-named resource families', () async {
    workspace.writePubspec(name: 'root');
    workspace.write('melos.yaml', 'name: fixture\npackages: [packages/*]\n');
    writeL10n(workspace, prefix: 'packages/a', packageName: 'a');
    writeL10n(workspace, prefix: 'packages/b', packageName: 'b');
    workspace.write('packages/b/lib/main.dart', '''
import 'package:a/l10n/app_localizations.dart' as a;
import 'l10n/app_localizations.dart' as b;
void main() { print(a.AppLocalizations.of(Object()).used); print(b.AppLocalizations.of(Object()).dead); }
''');
    final result = await analyze();
    expect(
      result.findings
          .map((f) => (f.packageName, f.stableId.split('|l10n:').last))
          .toSet(),
      {('a', 'dead'), ('b', 'used')},
    );
    final scoped = await analyze(packages: {'a'});
    expect(scoped.findings, hasLength(1));
    expect(keys(scoped), {'dead'});
  });

  test('dynamic access retains matching keys and emits a warning', () async {
    writeL10n(workspace);
    workspace.write('lib/main.dart', '''
void main() { dynamic value = Object(); print(value.used); }
''');
    final result = await analyze();
    expect(keys(result), {'dead'});
    expect(result.analysisWarnings, contains(contains('Localization use')));
  });

  test(
    'external consumers conservatively retain escaping translation families',
    () async {
      writeL10n(workspace);
      workspace.write('lib/main.dart', '''
import 'l10n/app_localizations.dart';
void main() { print(AppLocalizations.of(Object())); }
''');
      final result = await analyze();
      expect(keys(result), isEmpty);
      expect(result.analysisWarnings, contains(contains('unknown consumer')));
    },
  );

  test('object-pattern getters and generic bounds retain exact keys', () async {
    writeL10n(workspace);
    workspace.write('lib/main.dart', """
import 'l10n/app_localizations.dart';
String read<T extends AppLocalizations>(T value) => value.used;
void recursive<T extends Comparable<T>>(T value) { print(value); }
void main() {
  final AppLocalizations(:used) = AppLocalizations.of(Object());
  print(used);
  print(read(AppLocalizations.of(Object())));
  recursive(1);
}
""");
    final result = await analyze();
    expect(keys(result), {'dead'});
    expect(result.analysisWarnings, isEmpty);
  });

  test('unproven function values and abstract consumers retain keys', () async {
    writeL10n(workspace);
    workspace.write('lib/main.dart', """
import 'l10n/app_localizations.dart';
abstract class Consumer { void consume(AppLocalizations value); }
void invoke(void Function(AppLocalizations) callback, Consumer consumer) {
  callback(AppLocalizations.of(Object()));
  consumer.consume(AppLocalizations.of(Object()));
}
void main() {}
""");
    final result = await analyze();
    expect(keys(result), isEmpty);
    expect(result.analysisWarnings, contains(contains('unknown consumer')));
  });

  test('escaping one resource family does not hide another family', () async {
    workspace.writePubspec(name: 'root');
    workspace.write('melos.yaml', 'name: fixture\npackages: [packages/*]\n');
    writeL10n(workspace, prefix: 'packages/a', packageName: 'a');
    writeL10n(workspace, prefix: 'packages/b', packageName: 'b');
    workspace.write('packages/a/lib/main.dart', """
import 'l10n/app_localizations.dart';
void main() { print(AppLocalizations.of(Object()) as dynamic); }
""");
    final result = await analyze();
    expect(result.findings.map((f) => f.packageName).toSet(), {'b'});
    expect(keys(result), {'used', 'dead'});
    expect(result.analysisWarnings, isNotEmpty);
  });

  test(
    'third-party configurations are not mistaken for standard gen-l10n',
    () async {
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter:\n  generate: true\nflutter_intl:\n  enabled: true\n',
      );
      workspace.write('lib/l10n/intl_en.arb', '{"hello":"Hello"}');
      expect((await analyze()).findings, isEmpty);
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter:\n  generate: true\n',
      );
      workspace.write('slang.yaml', 'input_file_pattern: .arb\n');
      expect((await analyze()).findings, isEmpty);
    },
  );

  test('a broken secondary locale also fails closed', () async {
    writeL10n(workspace);
    workspace.write('lib/l10n/app_ja.arb', '{"@@locale":123,"used":"Used"}');
    await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
  });

  test('metadata, Unicode, CRLF, escaped keys and stable IDs', () async {
    writeL10n(workspace, messages: {'used': 'Used', 'title': '日本語'});
    workspace.write(
      'lib/l10n/app_en.arb',
      '{\r\n  "@@locale": "en",\r\n  "used": "Used",\r\n  "@used": {"description":"注釈"},\r\n  "ti\\u0074le": "日本語"\r\n}\r\n',
    );
    final first = await analyze();
    final title = first.findings.singleWhere(
      (f) => f.stableId.endsWith('l10n:title'),
    );
    expect((title.line, title.column, title.length), (5, 3, 12));
    workspace.write(
      'lib/l10n/app_en.arb',
      '{"title":"Changed", "used":"Used"}',
    );
    expect(
      (await analyze()).findings
          .singleWhere((f) => f.stableId.endsWith('l10n:title'))
          .stableId,
      title.stableId,
    );
    final baseline = Baseline.fromFindings(
      first.findings,
      rootPath: workspace.path,
    );
    expect(baseline.contains(title, rootPath: workspace.path), isTrue);
  });

  test(
    'suppression uses ARB paths and names; repeated runs have no stale uses',
    () async {
      writeL10n(workspace);
      workspace.write('kareki-config.yaml', 'exclude:\n  names: [dead]\n');
      expect(keys(await analyze()), {'used'});
      workspace.write(
        'kareki-config.yaml',
        'exclude:\n  files: ["**/*.arb"]\n',
      );
      expect(keys(await analyze()), isEmpty);
      workspace.write('kareki-config.yaml', '{}');
      workspace.write(
        'lib/main.dart',
        "import 'l10n/app_localizations.dart';\nvoid main() { print(AppLocalizations.of(Object()).used); }",
      );
      expect(keys(await analyze()), {'dead'});
      workspace.write('lib/main.dart', 'void main() {}');
      expect(keys(await analyze()), {'used', 'dead'});
    },
  );

  test(
    'rule disabled skips dedicated validation; other generators are not l10n',
    () async {
      writeL10n(workspace);
      workspace.write('lib/l10n/app_en.arb', '{"missing":"Missing"}');
      expect((await analyze(rules: {RuleId.unusedFile})).findings, isEmpty);
      workspace.write(
        'kareki-config.yaml',
        'ignore:\n  rules: [unused_l10n]\n',
      );
      expect((await analyze()).findings, isEmpty);
      workspace.dispose();
      workspace = TestWorkspace.create('kareki_not_l10n_');
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter:\n  generate: true\n',
      );
      expect((await analyze()).findings, isEmpty);
    },
  );

  test('removing all template keys detects leftover generated API', () async {
    writeL10n(workspace);
    workspace.write('lib/l10n/app_en.arb', '{}');
    await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
  });

  test('empty template needs no generated API', () async {
    writeL10n(workspace, messages: {});
    expect(keys(await analyze()), isEmpty);
  });

  for (final content in [
    '{',
    '[]',
    '{"used":"a","used":"b"}',
    '{"used":123}',
    '{"bad-key":"Bad"}',
  ]) {
    test('invalid ARB fails closed: $content', () async {
      writeL10n(workspace);
      workspace.write('lib/l10n/app_en.arb', content);
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
    });
  }

  for (final config in [
    '[]',
    '[',
    'arb-dir: 123',
    'output-class: false',
    'nullable-getter: invalid',
    'output-localization-file: nested/output.dart',
    'output-dir: ../elsewhere',
    'template-arb-file: missing.arb',
    'synthetic-package: true',
  ]) {
    test(
      'invalid or unsupported configuration fails closed: $config',
      () async {
        writeL10n(workspace);
        workspace.write('l10n.yaml', config);
        await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      },
    );
  }

  for (final api in [
    '',
    'class Wrong {}',
    'abstract class AppLocalizations { String get used; }',
    'abstract class AppLocalizations { String get used; String get dead; String get stale; }',
  ]) {
    test('missing class or stale API fails closed: $api', () async {
      writeL10n(workspace);
      workspace.write('lib/l10n/app_localizations.dart', api);
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
    });
  }
}
