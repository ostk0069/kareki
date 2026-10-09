import 'package:kareki/src/generated/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_gen_l10n_', bootstrap: false);
    workspace.write('pubspec.yaml', 'name: app\nflutter:\n  generate: true\n');
  });
  tearDown(() => workspace.dispose());

  Set<String> outputs() => flutterLocalizationOutputs(
    workspace.path,
  ).map((path) => p.relative(path, from: workspace.path)).toSet();

  test('default and explicitly configured outputs use ARB locale evidence', () {
    workspace.write('lib/l10n/app_en.arb', '{}');
    workspace.write('lib/l10n/app_zh_Hant_TW.arb', '{}');
    workspace.write('lib/l10n/anything.arb', '{"@@locale":"es_419"}');
    workspace.write('lib/l10n/unrelated.txt', '{}');
    workspace.write('lib/l10n/nested/app_fr.arb', '{}');
    expect(outputs(), {
      'lib/l10n/app_localizations.dart',
      'lib/l10n/app_localizations_en.dart',
      'lib/l10n/app_localizations_zh_Hant_TW.dart',
      'lib/l10n/app_localizations_zh.dart',
      'lib/l10n/app_localizations_es_419.dart',
      'lib/l10n/app_localizations_es.dart',
    });
    workspace.write('l10n.yaml', '''
arb-dir: translations
output-dir: .
output-localization-file: strings.custom.dart
''');
    workspace.write('translations/app_en.arb', '{}');
    expect(outputs(), {'strings.custom.dart', 'strings_en.custom.dart'});
  });

  test('without generation enabled same-named sources remain ordinary', () {
    workspace.write('lib/l10n/app_en.arb', '{}');
    for (final pubspec in [
      '',
      'name: app',
      'name: app\nflutter:\n  generate: false',
    ]) {
      workspace.write('pubspec.yaml', pubspec);
      expect(outputs(), isEmpty);
    }
  });

  test('missing or invalid ARB inputs cannot exempt sources', () {
    expect(outputs(), isEmpty);
    workspace.write('lib/l10n/broken.arb', '{');
    workspace.write('lib/l10n/list.arb', '[]');
    workspace.write('lib/l10n/app_en.arb', '{"@@locale":123}');
    workspace.write('lib/l10n/no_locale_match.arb', '{}');
    workspace.write('lib/l10n/path.arb', '{"@@locale":"../manual"}');
    expect(outputs(), isEmpty);
  });

  test(
    'unsupported or escaping output configurations do not exempt sources',
    () {
      workspace.write('lib/l10n/app_en.arb', '{}');
      for (final config in [
        '[]',
        'synthetic-package: true',
        'arb-dir: 123',
        'output-dir: false',
        'output-localization-file: []',
        'arb-dir: ../elsewhere',
        'output-dir: ../elsewhere',
        'output-localization-file: nested/messages.dart',
        'output-localization-file: messages.txt',
        'output-localization-file: .dart',
      ]) {
        workspace.write('l10n.yaml', config);
        expect(outputs(), isEmpty, reason: config);
      }
    },
  );
}
