import 'dart:convert';

import 'test_workspace.dart';

/// Minimal gen-l10n API shape for fast, SDK-independent resolved tests.
void writeL10n(
  TestWorkspace workspace, {
  String prefix = '',
  String packageName = 'runner_fixture',
  String className = 'AppLocalizations',
  String arbDir = 'lib/l10n',
  String outputDir = 'lib/l10n',
  String template = 'app_en.arb',
  String outputFile = 'app_localizations.dart',
  Map<String, String> messages = const {'used': 'Used', 'dead': 'Dead'},
  Map<String, String> methods = const {},
  bool configure = true,
}) {
  final base = prefix.isEmpty ? '' : '$prefix/';
  workspace.write('${base}pubspec.yaml', '''
name: $packageName
environment:
  sdk: '>=3.10.0 <4.0.0'
flutter:
  generate: true
''');
  if (configure) {
    workspace.write('${base}l10n.yaml', '''
arb-dir: $arbDir
output-dir: $outputDir
template-arb-file: $template
output-localization-file: $outputFile
output-class: $className
''');
  }
  workspace.write('$base$arbDir/$template', jsonEncode(messages));
  final members = messages.keys
      .map(
        (name) => methods.containsKey(name)
            ? 'String $name(${methods[name]});'
            : 'String get $name;',
      )
      .join('\n');
  workspace.write('$base$outputDir/$outputFile', '''
abstract class $className {
  const $className();
  static $className of(Object context) => throw UnimplementedError();
  static const supportedLocales = ['en'];
  static Object get delegate => Object();
  $members
}
''');
  final dot = outputFile.indexOf('.');
  final localeFile =
      '${outputFile.substring(0, dot)}_en${outputFile.substring(dot)}';
  final implementations = messages.keys
      .map(
        (name) => methods.containsKey(name)
            ? "@override String $name(${methods[name]}) => '$name';"
            : "@override String get $name => '$name';",
      )
      .join('\n');
  workspace.write('$base$outputDir/$localeFile', '''
import '$outputFile';
class ${className}En extends $className {
  $implementations
}
''');
}
