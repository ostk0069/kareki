import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() => workspace = TestWorkspace.create('kareki_assets_'));
  tearDown(() => workspace.dispose());

  void setup({String prefix = '', String name = 'runner_fixture'}) {
    workspace.write('${prefix}pubspec.yaml', '''
name: $name
environment:
  sdk: '>=3.10.0 <4.0.0'
flutter:
  assets:
    - assets/images/
    - path: assets/data.json
      flavors: [dev]
  fonts:
    - family: UsedFont
      fonts:
        - asset: fonts/regular.ttf
        - asset: fonts/bold.ttf
          weight: 700
    - family: DeadFont
      fonts:
        - asset: fonts/dead.ttf
''');
    for (final file in [
      'used.png',
      'dead.png',
      '2.0x/used.png',
      '3.0x/dead.png',
      'nested/not_bundled.png',
    ]) {
      workspace.write('${prefix}assets/images/$file', 'image');
    }
    workspace.write('${prefix}assets/data.json', '{}');
    workspace.write('${prefix}lib/gen/assets.gen.dart', r'''
// GENERATED CODE - DO NOT MODIFY BY HAND
// FlutterGen
class Assets {
  static const images = $AssetsImagesGen();
  static const data = 'assets/data.json';
}
class $AssetsImagesGen {
  const $AssetsImagesGen();
  AssetGenImage get used => const AssetGenImage('assets/images/used.png');
  AssetGenImage get dead => const AssetGenImage('assets/images/dead.png');
  List<AssetGenImage> get values => [used, dead];
}
class AssetGenImage {
  const AssetGenImage(this.path);
  final String path;
  Object image() => Object();
}
''');
    workspace.write('${prefix}lib/gen/fonts.gen.dart', '''
// GENERATED CODE - DO NOT MODIFY BY HAND
// FlutterGen
class FontFamily {
  static const usedFont = 'UsedFont';
  static const deadFont = 'DeadFont';
}
''');
  }

  Future<RunResult> analyze({Set<String>? packages, Set<String>? rules}) =>
      KarekiRunner().run(
        RunRequest(
          rootPath: workspace.path,
          config: KarekiConfig.load(workspace.path),
          enabledRules: rules ?? {RuleId.unusedAsset},
          includePackages: packages,
        ),
      );

  Set<String> unused(RunResult result) =>
      result.findings.map((f) => f.message).toSet();

  test(
    'individual FlutterGen image and font uses exclude generated literals',
    () async {
      setup();
      workspace.write('lib/main.dart', '''
import 'gen/assets.gen.dart';
import 'gen/fonts.gen.dart';
void main() {
  final images = Assets.images;
  print(images.used.image());
  print(FontFamily.usedFont);
  // Assets.images.dead
  print('Assets.images.dead');
}
''');
      final result = await analyze();
      expect(unused(result), {
        "Unused asset 'assets/images/dead.png'.",
        "Unused asset 'assets/data.json'.",
        "Unused font family 'DeadFont'.",
      });
      expect(
        result.findings.every(
          (f) =>
              f.ruleId == RuleId.unusedAsset &&
              f.filePath.endsWith('pubspec.yaml') &&
              f.line > 0,
        ),
        isTrue,
      );
    },
  );

  test('imports alone retain no resources', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      "import 'gen/assets.gen.dart';\nvoid main() {}\n",
    );
    expect((await analyze()).findings, hasLength(5));
  });

  test('values enumerations and raw string constants', () async {
    setup();
    workspace.write('lib/main.dart', '''
import 'gen/assets.gen.dart';
const family = 'Used' + 'Font';
void main() {
  print(Assets.images.values);
  print(Assets.data);
  print(family);
}
''');
    expect(unused(await analyze()), {"Unused font family 'DeadFont'."});
  });

  test('container escape conservatively retains its images', () async {
    setup();
    workspace.write('lib/main.dart', '''
import 'gen/assets.gen.dart';
void main() { print(Assets.images); }
''');
    expect(unused(await analyze()), {
      "Unused asset 'assets/data.json'.",
      "Unused font family 'DeadFont'.",
      "Unused font family 'UsedFont'.",
    });
  });

  test(
    'raw paths, constants, interpolation, tests and unreachable bodies count',
    () async {
      setup();
      workspace.write(
        'lib/main.dart',
        "void main() {}\nvoid dead() { print('assets/data.json'); print('UsedFont'); }",
      );
      workspace.write('test/sample_test.dart', r'''
void main() {
  const directory = 'assets/images/';
  print('${directory}used.png');
}
''');
      expect(unused(await analyze()), {
        "Unused asset 'assets/images/dead.png'.",
        "Unused font family 'DeadFont'.",
      });
    },
  );

  test('direct resolution variant paths retain the logical image', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      "void main() { print('assets/images/2.0x/used.png'); }",
    );
    expect((await analyze()).findings, hasLength(4));
  });

  test('dynamic prefixes retain only matching assets with a warning', () async {
    setup();
    workspace.write('lib/main.dart', r'''
void main(List<String> args) { print('assets/images/${args.first}.png'); }
''');
    final result = await analyze();
    expect(result.analysisWarnings, hasLength(1));
    expect(unused(result), {
      "Unused asset 'assets/data.json'.",
      "Unused font family 'DeadFont'.",
      "Unused font family 'UsedFont'.",
    });
  });

  test('workspace package identity and reporting filter', () async {
    workspace.writePubspec(name: 'root');
    workspace.write('melos.yaml', 'packages:\n  - .\n  - packages/*\n');
    setup(prefix: 'packages/a/', name: 'a');
    setup(prefix: 'packages/b/', name: 'b');
    workspace.write('lib/main.dart', '''
import 'package:a/gen/assets.gen.dart';
import 'package:a/gen/fonts.gen.dart';
void main() { print(Assets.images.used.path); print(FontFamily.usedFont); }
''');
    final result = await analyze(packages: {'a'});
    expect(result.findings, hasLength(3));
    expect(result.findings.every((f) => f.packageName == 'a'), isTrue);
    expect((await analyze(packages: {'b'})).findings, hasLength(5));
  });

  test('package-qualified raw paths retain only their owner', () async {
    workspace.writePubspec(name: 'root');
    workspace.write('melos.yaml', 'packages:\n  - .\n  - packages/*\n');
    setup(prefix: 'packages/a/', name: 'a');
    setup(prefix: 'packages/b/', name: 'b');
    workspace.write(
      'lib/main.dart',
      "void main() { print('packages/a/assets/images/used.png'); print('packages/a/UsedFont'); }",
    );
    expect((await analyze(packages: {'a'})).findings, hasLength(3));
    expect((await analyze(packages: {'b'})).findings, hasLength(5));
  });

  test('exclude paths, names and ignore rules', () async {
    setup();
    workspace.write('lib/main.dart', 'void main() {}');
    workspace.write('kareki-config.yaml', '''
exclude:
  files: ['assets/images/**']
  names: [DeadFont, UsedFont]
''');
    expect(unused(await analyze()), {"Unused asset 'assets/data.json'."});
    workspace.write('kareki-config.yaml', 'ignore:\n  rules: [unused_asset]\n');
    expect((await analyze()).findings, isEmpty);
  });

  test(
    'custom generated paths and names, patterns and package fonts',
    () async {
      setup();
      workspace.write('lib/custom/resources.dart', r"""
// GENERATED CODE - DO NOT MODIFY BY HAND
// FlutterGen
class CustomResources {
  String get chosen => 'assets/images/used.png';
}
class CustomFonts {
  static const package = 'runner_fixture';
  static const chosen = 'packages/$package/UsedFont';
}
""");
      workspace.write('lib/main.dart', """
import 'custom/resources.dart';
void main() {
  final CustomResources(:chosen) = CustomResources();
  print(chosen);
  print(CustomFonts.chosen);
}
""");
      expect(unused(await analyze()), {
        "Unused asset 'assets/images/dead.png'.",
        "Unused asset 'assets/data.json'.",
        "Unused font family 'DeadFont'.",
      });
    },
  );

  test(
    'explicit package argument disambiguates identical paths and fonts',
    () async {
      workspace.writePubspec(name: 'root');
      workspace.write('melos.yaml', 'packages: [., packages/*]');
      setup(prefix: 'packages/a/', name: 'a');
      setup(prefix: 'packages/b/', name: 'b');
      workspace.write('packages/b/lib/main.dart', """
void consume(String path, {required String package}) {}
void font({required String fontFamily, required String fontPackage}) {}
void main() {
  consume('assets/images/used.png', package: 'a');
  font(fontFamily: 'UsedFont', fontPackage: 'a');
}
""");
      expect((await analyze(packages: {'a'})).findings, hasLength(3));
      expect((await analyze(packages: {'b'})).findings, hasLength(5));
    },
  );

  test('other generated sources remain consumers', () async {
    setup();
    workspace.write('lib/use.g.dart', """
// GENERATED CODE - DO NOT MODIFY BY HAND
void use() { print('assets/data.json'); }
""");
    workspace.write('lib/main.dart', 'void main() {}');
    expect((await analyze()).findings, hasLength(4));
  });

  test(
    'a FlutterGen mention in user code does not turn it into generated code',
    () async {
      setup();
      workspace.write('lib/main.dart', """
// FlutterGen is optional here.
void main() { print('assets/data.json'); }
""");
      expect((await analyze()).findings, hasLength(4));
    },
  );

  test('unresolved sources fail closed', () async {
    setup();
    workspace.write('lib/main.dart', "import 'missing.dart'; void main() {}");
    expect(analyze(), throwsA(isA<ResolvedAnalysisException>()));
  });

  test('no Dart sources reports all declared resources', () async {
    workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter:
  assets: [assets/file.json]
''');
    expect(unused(await analyze()), {"Unused asset 'assets/file.json'."});
  });

  test(
    'malformed asset declarations fail closed only when rule enabled',
    () async {
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter:\n  assets: [42]\n',
      );
      workspace.write('lib/main.dart', 'void main() {}');
      expect(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      expect((await analyze(rules: {RuleId.unusedFile})).findings, isEmpty);
    },
  );
}
