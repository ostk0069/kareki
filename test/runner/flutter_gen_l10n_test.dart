import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  final flutter = Platform.environment['KAREKI_FLUTTER_BIN'];
  for (final configuration in ['defaults', 'custom', 'named-deferred']) {
    test(
      'real flutter gen-l10n: $configuration',
      () async {
        final workspace = TestWorkspace.create(
          'kareki_real_l10n_',
          bootstrap: false,
        );
        addTearDown(workspace.dispose);
        final custom = configuration != 'defaults';
        final named = configuration == 'named-deferred';
        final input = custom ? 'translations' : 'lib/l10n';
        final output = custom ? 'lib/generated' : 'lib/l10n';
        final className = custom ? 'L10n' : 'AppLocalizations';
        final outputFile = custom ? 'l10n.dart' : 'app_localizations.dart';
        final template = custom ? 'intl_messages_ja.arb' : 'app_en.arb';
        workspace.write('pubspec.yaml', '''
name: real_localization
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
flutter:
  generate: true
''');
        if (custom) {
          workspace.write('l10n.yaml', '''
arb-dir: $input
output-dir: $output
template-arb-file: $template
output-localization-file: $outputFile
output-class: $className
nullable-getter: false
use-deferred-loading: $named
use-named-parameters: $named
''');
        }
        final messages = <String, Object>{
          '@@locale': custom ? 'ja' : 'en',
          'used': 'Used',
          'dead': 'Dead',
          'hello': 'Hello {name}',
          '@hello': {
            'placeholders': {
              'name': {'type': 'String'},
            },
          },
          'items': '{count, plural, =0{None} other{Items}}',
          '@items': {
            'placeholders': {
              'count': {'type': 'int'},
            },
          },
          'person': '{gender, select, male{He} other{They}}',
          '@person': {
            'placeholders': {
              'gender': {'type': 'String'},
            },
          },
        };
        workspace.write('$input/$template', jsonEncode(messages));
        workspace.write(
          '$input/app_zh.arb',
          jsonEncode({...messages, '@@locale': 'zh'}),
        );
        workspace.write(
          '$input/app_zh_Hant_TW.arb',
          jsonEncode({...messages, '@@locale': 'zh_Hant_TW'}),
        );
        workspace.write('lib/main.dart', '''
import 'package:flutter/widgets.dart';
import '${custom ? 'generated' : 'l10n'}/$outputFile';
$className useL10n(BuildContext context) => $className.of(context)${custom ? '' : '!'};
Widget label(BuildContext context) {
  final l10n = useL10n(context);
  return Text(l10n.used + l10n.hello(${named ? 'name: ' : ''}'Name') +
      l10n.items(${named ? 'count: ' : ''}2) + l10n.person(${named ? 'gender: ' : ''}'other'));
}
void main() {}
''');
        for (final args in [
          const ['pub', 'get'],
          const ['gen-l10n'],
        ]) {
          final result = await Process.run(
            flutter!,
            args,
            workingDirectory: workspace.path,
          );
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
        }
        final result = await KarekiRunner().run(
          RunRequest(
            rootPath: workspace.path,
            config: KarekiConfig.defaults(),
            enabledRules: {RuleId.unusedL10n},
          ),
        );
        expect(result.analysisWarnings, isEmpty);
        expect(result.findings, hasLength(1));
        expect(result.findings.single.stableId, endsWith('|l10n:dead'));
        expect(
          result.findings.single.filePath,
          p.join(workspace.path, input, template),
        );
      },
      skip: flutter == null
          ? 'Set KAREKI_FLUTTER_BIN to run actual Flutter generation.'
          : false,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
