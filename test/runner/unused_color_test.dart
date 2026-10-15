import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/assets/flutter_assets.dart';
import 'package:kareki/src/assets/non_dart_asset_usage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() => workspace = TestWorkspace.create('kareki_colors_'));
  tearDown(() => workspace.dispose());

  void setup({
    String prefix = '',
    String name = 'runner_fixture',
    String output = 'lib/gen/',
    String className = 'ColorName',
  }) {
    workspace.write('${prefix}pubspec.yaml', '''
name: $name
environment:
  sdk: '>=3.10.0 <4.0.0'
flutter_gen:
  output: $output
  colors:
    inputs: [colors.xml]
    outputs:
      class_name: $className
''');
    workspace.write('${prefix}colors.xml', '''
<?xml version="1.0"?>
<resources>
  <!-- <color name="comment">#000000</color> -->
  <color name="used_color">#123456</color>
  <color name="dead_color">#123456</color>
  <color name="brand" type="material material-accent">#abcdef</color>
  <color name="accent_only" type="material-accent">#aabbcc</color>
</resources>
''');
    workspace.write('$prefix${output}colors.gen.dart', '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// FlutterGen
class Color { const Color(this.value); final int value; }
class MaterialColor extends Color { const MaterialColor(super.value); }
class MaterialAccentColor extends Color { const MaterialAccentColor(super.value); }
abstract final class $className {
  static const usedColor = Color(0xff123456);
  static const deadColor = Color(0xff123456);
  static const brand = MaterialColor(0xffabcdef);
  static const brandAccent = MaterialAccentColor(0xffabcdef);
  static const accentOnlyAccent = MaterialAccentColor(0xffaabbcc);
}
''');
  }

  Future<RunResult> analyze({Set<String>? packages}) => KarekiRunner().run(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: {RuleId.unusedAsset},
      includePackages: packages,
    ),
  );
  Set<String> messages(RunResult result) =>
      result.findings.map((f) => f.message).toSet();
  List<FlutterAsset> load() =>
      FlutterAsset.load(workspace.path, 'runner_fixture');

  test(
    'color identity, aliases, accent members and XML source spans',
    () async {
      setup();
      workspace.write('lib/main.dart', '''
import 'gen/colors.gen.dart' as palette;
const alias = palette.ColorName.usedColor;
void main() {
  print(alias);
  print(palette.ColorName.brandAccent);
  print(palette.ColorName.accentOnlyAccent);
  print('dead_color');
  print('#123456');
  // palette.ColorName.deadColor
}
''');
      final result = await analyze();
      expect(messages(result), {"Unused color 'dead_color'."});
      final finding = result.findings.single;
      expect(finding.filePath, p.join(workspace.path, 'colors.xml'));
      expect(finding.line, 5);
      expect(finding.column, 3);
      expect(finding.length, '<color name="dead_color">'.length);
      expect(finding.stableId, endsWith('|color:dead_color'));
      expect(result.analysisWarnings, isEmpty);
    },
  );

  test(
    'material base alone retains both generated members of its XML color',
    () async {
      setup();
      workspace.write('lib/main.dart', '''
import 'gen/colors.gen.dart';
void main() { print(ColorName.brand); }
''');
      expect(messages(await analyze()), {
        "Unused color 'used_color'.",
        "Unused color 'dead_color'.",
        "Unused color 'accent_only'.",
      });
    },
  );

  test('imports and class references alone do not retain colors', () async {
    setup();
    workspace.write('lib/main.dart', '''
import 'gen/colors.gen.dart';
void main() { print(ColorName); print('AssetManifest.json'); }
''');
    expect((await analyze()).findings, hasLength(4));
    expect(NonDartAssetUsage.collect(workspace.path, load()), isEmpty);
  });

  test(
    'reexports and cross-package references preserve source identity',
    () async {
      workspace.write(
        'pubspec.yaml',
        'name: root\nworkspace: [app, palette]\n',
      );
      setup(prefix: 'palette/', name: 'palette', className: 'MyColors');
      setup(prefix: 'app/', name: 'app');
      workspace.write(
        'app/lib/palette.dart',
        "export 'package:palette/gen/colors.gen.dart';\n",
      );
      workspace.write('app/lib/main.dart', '''
import 'palette.dart';
import 'gen/colors.gen.dart';
void main() { print(MyColors.usedColor); print(ColorName.deadColor); }
''');
      final result = await analyze(packages: {'palette'});
      expect(messages(result), {
        "Unused color 'dead_color'.",
        "Unused color 'brand'.",
        "Unused color 'accent_only'.",
      });
      expect(result.findings.every((f) => f.packageName == 'palette'), isTrue);
    },
  );

  test(
    'build.yaml deep overrides, custom output outside lib and old headers',
    () async {
      setup(output: 'generated/', className: 'CustomColors');
      final pubspec = File(p.join(workspace.path, 'pubspec.yaml'));
      pubspec.writeAsStringSync(
        pubspec
            .readAsStringSync()
            .replaceAll('generated/', 'lib/old/')
            .replaceAll('CustomColors', 'OldColors'),
      );
      workspace.write('build.yaml', r'''
targets:
  ignored: {}
  $default:
    builders:
      other: {options: {colors: {inputs: [missing.xml]}}}
      flutter_gen_runner:
        options:
          output: generated/
          colors:
            outputs: {class_name: CustomColors}
''');
      final output = File(p.join(workspace.path, 'generated/colors.gen.dart'));
      output.writeAsStringSync(
        output.readAsStringSync().replaceAll(
          '// GENERATED CODE - DO NOT MODIFY BY HAND\n// FlutterGen\n',
          '',
        ),
      );
      workspace.write('bin/main.dart', '''
import '../generated/colors.gen.dart';
void main() { print(CustomColors.usedColor); }
''');
      expect((await analyze()).findings, hasLength(3));
    },
  );

  test(
    'missing output, wrong class and stale member API fail closed',
    () async {
      setup();
      workspace.write('lib/main.dart', 'void main() {}\n');
      final output = File(p.join(workspace.path, 'lib/gen/colors.gen.dart'));
      final content = output.readAsStringSync();
      output.deleteSync();
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      output.writeAsStringSync(
        content.replaceAll('class ColorName', 'class WrongName'),
      );
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      output.writeAsStringSync(content.replaceAll('deadColor', 'oldColor'));
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      output.writeAsStringSync(
        content.replaceAll('static const deadColor', 'static final deadColor'),
      );
      await expectLater(analyze(), throwsA(isA<ResolvedAnalysisException>()));
    },
  );

  test('XML exclusions and names use the original resource', () async {
    setup();
    workspace.write('lib/main.dart', 'void main() {}\n');
    workspace.write('kareki-config.yaml', '''
exclude:
  names: [used_color, brand, accent_only]
''');
    final result = await analyze();
    expect(messages(result), {"Unused color 'dead_color'."});
    workspace.write('kareki-config.yaml', 'exclude:\n  files: [colors.xml]\n');
    expect((await analyze()).findings, isEmpty);
  });

  test('disabled colors and empty config need no generated output', () async {
    workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter_gen:
  colors: {enabled: false, inputs: [missing.xml]}
''');
    workspace.write('lib/main.dart', 'void main() {}\n');
    expect((await analyze()).findings, isEmpty);
    for (final config in ['{}', '{colors: {}}', '{colors: {inputs: []}}']) {
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter_gen: $config\n',
      );
      expect(load(), isEmpty);
    }
  });

  test(
    'ambiguous builder options fail closed; null overrides preserve settings',
    () {
      setup();
      workspace.write('build.yaml', r'''
targets:
  $default:
    builders:
      flutter_gen:
        options: {output: null, colors: {outputs: null}}
''');
      expect(load(), hasLength(4));
      workspace.write('build.yaml', r'''
targets:
  $default:
    builders:
      flutter_gen: {options: {colors: {inputs: [colors.xml]}}}
      flutter_gen_runner: {options: {colors: {inputs: [other.xml]}}}
''');
      expect(load, throwsFormatException);
      workspace.write('pubspec.yaml', 'name: runner_fixture\n');
      workspace.write('build.yaml', r'''
targets:
  $default:
    builders:
      flutter_gen: {options: {assets: {enabled: true}}}
      flutter_gen_runner: {options: {assets: {enabled: true}}}
''');
      expect(load(), isEmpty);
    },
  );

  test(
    'duplicates keep first XML definition and match FlutterGen word splitting',
    () {
      workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter_gen:
  colors:
    inputs: [colors.xml, other.xml, colors.xml]
''');
      workspace.write('colors.xml', '''
<resources>
<color name="RGB">#112233</color>
<color name="myURL">#00112233</color>
<color name="milk&#95;tea">#aabbcc</color>
<color name="dash-name">#abcdef</color>
<color name="x.y@z">#ffffff</color>
</resources>
''');
      workspace.write(
        'other.xml',
        '<resources><color name="RGB">#abcdef</color></resources>',
      );
      final colors = load();
      expect(colors.map((a) => a.color!.members.single), [
        'rgb',
        'myURL',
        'milkTea',
        'dashName',
        'xYZ',
      ]);
      expect(colors.first.definitionPath, endsWith('colors.xml'));
      expect(colors.first.color!.offset, greaterThan(0));
    },
  );

  for (final entry in <String, String>{
    'colors must be a map': 'colors: []',
    'enabled must be boolean': 'colors: {enabled: 42}',
    'outputs must be a map': 'colors: {inputs: [], outputs: []}',
    'inputs must be a list': 'colors: {inputs: 42}',
    'class must be a string': 'colors: {inputs: [], outputs: {class_name: 42}}',
    'output must be a string': 'output: 42\n  colors: {inputs: []}',
    'output must stay inside package':
        'output: ../outside\n  colors: {inputs: []}',
    'input must stay inside package': 'colors: {inputs: [../outside.xml]}',
    'input must be XML': 'colors: {inputs: [colors.json]}',
    'input must be a string': 'colors: {inputs: [42]}',
    'input must exist': 'colors: {inputs: [missing.xml]}',
  }.entries) {
    test(entry.key, () {
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter_gen:\n  ${entry.value}\n',
      );
      expect(
        load,
        throwsA(anyOf(isA<FormatException>(), isA<FileSystemException>())),
      );
    });
  }

  for (final entry in <String, String>{
    'malformed XML': '<resources><color></resources>',
    'missing name': '<color>#123456</color>',
    'empty name': '<color name="">#123456</color>',
    'invalid value': '<color name="red">nope</color>',
    'unknown type': '<color name="red" type="gradient">#123456</color>',
    'invalid identifier': '<color name="1red">#123456</color>',
    'empty identifier': '<color name="___">#123456</color>',
    'member collision':
        '<color name="a_b">#123456</color><color name="aB">#123456</color>',
  }.entries) {
    test(entry.key, () {
      setup();
      workspace.write('colors.xml', '<resources>${entry.value}</resources>');
      expect(load, throwsA(isA<Exception>()));
    });
  }
}
