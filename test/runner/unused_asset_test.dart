import 'dart:convert';
import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/assets/flutter_assets.dart';
import 'package:kareki/src/assets/non_dart_asset_usage.dart';
import 'package:path/path.dart' as p;
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

  test(
    'generated font identity and package-qualified interpolation stay isolated',
    () async {
      workspace.writePubspec(name: 'root');
      workspace.write('melos.yaml', 'packages: [., packages/*]');
      setup(prefix: 'packages/a/', name: 'a');
      setup(prefix: 'packages/b/', name: 'b');
      workspace.write('packages/b/lib/main.dart', r"""
import 'package:a/gen/fonts.gen.dart';
void consume(String path, {required String package}) {}
void main() {
  print(FontFamily.usedFont);
  const directory = 'assets/images/';
  consume('${directory}used.png', package: 'a');
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

  test(
    'literal paths in workflows, native config and scripts retain resources',
    () async {
      setup();
      workspace.write(
        '.github/workflows/build.yml',
        'steps: ["cp assets/images/used.png output.png"]',
      );
      workspace.write(
        'native/config.json',
        '{"image":"assets/images/dead.png"}',
      );
      workspace.write('tool/package.sh', 'cp assets/data.json bundled.json');
      workspace.write('native/fonts.xml', '<font>fonts/regular.ttf</font>');
      final result = await analyze();
      expect(unused(result), {"Unused font family 'DeadFont'."});
    },
  );

  test(
    'registrations, caches, binary files and unrelated basenames do not retain assets',
    () async {
      setup();
      workspace.write('lib/main.dart', 'void main() {}');
      workspace.write(
        '.dart_tool/cache/config.json',
        '{"path":"assets/images/used.png"}',
      );
      workspace.write('build/config.json', '{"path":"assets/images/dead.png"}');
      workspace.write('assets/image.png', 'assets/data.json');
      workspace.write('native/config.json', '{"image":"used.png"}');
      workspace.write('native/huge.json', 'x' * (1024 * 1024 + 1));
      expect((await analyze()).findings, hasLength(5));
    },
  );

  test('workflow paths resolve workspace-relative ownership', () async {
    workspace.writePubspec(name: 'root');
    workspace.write('melos.yaml', 'packages: [., packages/*]');
    setup(prefix: 'packages/a/', name: 'a');
    setup(prefix: 'packages/b/', name: 'b');
    workspace.write(
      '.github/workflows/build.yml',
      'steps: ["cp packages/a/assets/images/used.png out.png"]',
    );
    workspace.write(
      'packages/a/native/config.json',
      '{"image":"assets/images/dead.png"}',
    );
    expect((await analyze(packages: {'a'})).findings, hasLength(3));
    expect((await analyze(packages: {'b'})).findings, hasLength(5));
  });

  test('baseline/report metadata cannot count as resource usage', () async {
    setup();
    workspace.write('lib/main.dart', 'void main() {}');
    workspace.write(
      'reports/output.json',
      '{"tool":"kareki","findings":[{"message":"assets/images/used.png"}]}',
    );
    workspace.write(
      'reports/malformed.json',
      '{"tool":"kareki","findings": // assets/images/dead.png',
    );
    // A malformed report-shaped file remains ordinary source text.
    expect(unused(await analyze()), {
      "Unused asset 'assets/data.json'.",
      "Unused asset 'assets/images/used.png'.",
      "Unused font family 'UsedFont'.",
      "Unused font family 'DeadFont'.",
    });
  });

  test('large embedded SVG data is scanned without repeated backtracking', () {
    setup();
    workspace.write(
      'native/embedded.svg',
      '<svg><image href="data:image/png;base64,${'A' * 200000}"/><image href="assets/images/used.png"/></svg>',
    );
    final assets = FlutterAsset.load(workspace.path, 'runner_fixture');
    final used = NonDartAssetUsage.collect(workspace.path, assets);
    expect(used, {'runner_fixture|asset:assets/images/used.png'});
  }, timeout: const Timeout(Duration(seconds: 10)));

  test('quoted Unicode paths and file-relative native references', () async {
    workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter:
  assets:
    - assets/日本 語.png
    - assets/sibling.png
''');
    workspace.write('assets/日本 語.png', 'image');
    workspace.write('assets/sibling.png', 'image');
    workspace.write('native/config.json', '{"image":"assets/日本 語.png"}');
    workspace.write('assets/native.svg', '<image href="sibling.png"/>');
    expect((await analyze()).findings, isEmpty);
  });

  test(
    'unreadable text consumers fail closed instead of reporting unused assets',
    () async {
      setup();
      workspace.write('lib/main.dart', 'void main() {}');
      workspace.write('native/invalid.json', '{}');
      File(
        p.join(workspace.path, 'native/invalid.json'),
      ).writeAsBytesSync([255]);
      expect(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      expect((await analyze(rules: {RuleId.unusedFile})).findings, isEmpty);
    },
  );

  test('direct font-file loads retain their family', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      "void main() { print('fonts/bold.ttf'); }",
    );
    expect(unused(await analyze()), {
      "Unused asset 'assets/data.json'.",
      "Unused asset 'assets/images/used.png'.",
      "Unused asset 'assets/images/dead.png'.",
      "Unused font family 'DeadFont'.",
    });
  });

  test('FlutterGen references survive a symlinked workspace root', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      "import 'gen/assets.gen.dart'; void main() { print(Assets.images.used.path); }",
    );
    final link = Link('${workspace.path}_link')..createSync(workspace.path);
    addTearDown(link.deleteSync);
    final result = await KarekiRunner().run(
      RunRequest(
        rootPath: link.path,
        config: KarekiConfig.load(link.path),
        enabledRules: {RuleId.unusedAsset},
      ),
    );
    expect(unused(result), {
      "Unused asset 'assets/images/dead.png'.",
      "Unused asset 'assets/data.json'.",
      "Unused font family 'UsedFont'.",
      "Unused font family 'DeadFont'.",
    });
  });

  test(
    'adjacent strings, parenthesized qualifiers and uncertain package properties',
    () async {
      setup();
      workspace.write('lib/main.dart', """
class Config { const Config(this.name); final String name; }
void consume(String path, {required String package}) {}
void main(List<String> args) {
  print('assets/' 'data.json');
  consume('assets/images/used.png', package: ('runner_fixture'));
  final config = Config(args.first);
  consume('assets/images/dead.png', package: (config).name);
}
""");
      final result = await analyze();
      expect(unused(result), {
        "Unused font family 'UsedFont'.",
        "Unused font family 'DeadFont'.",
      });
      expect(result.analysisWarnings.single, contains('Unknown asset package'));
    },
  );

  test('returning a generated directory retains its members', () async {
    setup();
    workspace.write('lib/main.dart', """
import 'gen/assets.gen.dart';
Object directory() { return Assets.images; }
void skip() { return; }
void main() { print(directory()); skip(); }
""");
    expect(unused(await analyze()), {
      "Unused asset 'assets/data.json'.",
      "Unused font family 'UsedFont'.",
      "Unused font family 'DeadFont'.",
    });
  });

  test('older generated headers and DartDoc references', () async {
    setup();
    for (final file in ['assets.gen.dart', 'fonts.gen.dart']) {
      final generated = File(p.join(workspace.path, 'lib/gen', file));
      generated.writeAsStringSync(
        generated.readAsStringSync().replaceAll('// FlutterGen\n', ''),
      );
    }
    workspace.write('lib/main.dart', """
import 'gen/assets.gen.dart';
import 'gen/fonts.gen.dart';
/// See [Assets.images.dead].
void main() { print(Assets.images.used); print(FontFamily.usedFont); }
""");
    expect(unused(await analyze()), {
      "Unused asset 'assets/data.json'.",
      "Unused asset 'assets/images/dead.png'.",
      "Unused font family 'DeadFont'.",
    });
  });

  test('AssetManifest API is recognized by resolved library identity', () async {
    setup();
    final external = TestWorkspace.create(
      'kareki_manifest_api_',
      bootstrap: false,
    );
    addTearDown(external.dispose);
    // Minimal SDK-independent protocol fixture; the unrelated workspace type
    // below ensures that an identifier name alone cannot retain resources.
    external.write(
      'lib/src/services/asset_manifest.dart',
      'class AssetManifest { static void loadFromAssetBundle(Object bundle) {} }',
    );
    workspace.write(
      'lib/main.dart',
      "import 'package:flutter/src/services/asset_manifest.dart'; void main() { AssetManifest.loadFromAssetBundle(Object()); }",
    );
    final file = File(p.join(workspace.path, '.dart_tool/package_config.json'));
    final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    (config['packages'] as List).add({
      'name': 'flutter',
      'rootUri': external.directory.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    });
    file.writeAsStringSync(jsonEncode(config));
    final result = await analyze();
    expect(unused(result), {
      "Unused font family 'UsedFont'.",
      "Unused font family 'DeadFont'.",
    });
    expect(result.analysisWarnings.single, contains('Asset manifest consumer'));
    workspace.write(
      'lib/main.dart',
      'class AssetManifest { static void loadFromAssetBundle(Object bundle) {} } void main() { AssetManifest.loadFromAssetBundle(Object()); }',
    );
    expect((await analyze()).findings, hasLength(5));
  });

  test('font-manifest enumeration retains all fonts with a warning', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      "void main() { print('FontManifest.json'); }",
    );
    final result = await analyze();
    expect(
      result.findings.where(
        (finding) => finding.message.contains('font family'),
      ),
      isEmpty,
    );
    expect(result.analysisWarnings.single, contains('Font manifest consumer'));
  });

  test(
    'asset-manifest enumeration retains assets without retaining fonts',
    () async {
      setup();
      workspace.write(
        'lib/main.dart',
        "void main() { print('AssetManifest.bin'); }",
      );
      final result = await analyze();
      expect(unused(result), {
        "Unused font family 'UsedFont'.",
        "Unused font family 'DeadFont'.",
      });
      expect(
        result.analysisWarnings.single,
        contains('Asset manifest consumer'),
      );
    },
  );

  for (final mode in [
    'call',
    'constructor',
    'import',
    'comment',
    'other_manifest',
  ]) {
    test('external font-manifest consumer: $mode', () async {
      setup();
      final external = TestWorkspace.create(
        'kareki_font_consumer_',
        bootstrap: false,
      );
      addTearDown(external.dispose);
      external.write('pubspec.yaml', 'name: manifest_reader');
      external.write(
        'lib/reader.dart',
        "import 'src/fonts.dart'; class Reader { void run() => loadFonts(); }",
      );
      external.write('lib/src/fonts.dart', switch (mode) {
        'comment' => "// 'FontManifest.json'\nvoid loadFonts() {}",
        'other_manifest' => "void loadFonts() { print('OtherManifest.json'); }",
        _ => "void loadFonts() { print('FontManifest.json'); }",
      });
      workspace.write(
        'lib/main.dart',
        "import 'package:manifest_reader/reader.dart';\nvoid main() { ${mode == 'import'
            ? ''
            : mode == 'constructor'
            ? 'Reader();'
            : 'Reader().run();'} }",
      );
      final file = File(
        p.join(workspace.path, '.dart_tool/package_config.json'),
      );
      final config =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      (config['packages'] as List).add({
        'name': 'manifest_reader',
        'rootUri': external.directory.uri.toString(),
        'packageUri': 'lib/',
        'languageVersion': '3.10',
      });
      file.writeAsStringSync(jsonEncode(config));
      final result = await analyze();
      final retained = {'call', 'constructor'}.contains(mode);
      expect(
        result.findings
            .where((finding) => finding.message.contains('font family'))
            .length,
        retained ? 0 : 2,
      );
      expect(result.analysisWarnings.isNotEmpty, retained);
    });
  }

  test(
    'a used font retains its faces also registered as general assets',
    () async {
      workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter:
  assets: [fonts/]
  fonts:
    - family: Example
      fonts:
        - asset: fonts/regular.ttf
        - asset: fonts/bold.ttf
          weight: 700
''');
      workspace.write('fonts/regular.ttf', 'font');
      workspace.write('fonts/bold.ttf', 'font');
      workspace.write('lib/main.dart', "void main() { print('Example'); }");
      expect((await analyze()).findings, isEmpty);
    },
  );

  test('primitive const values do not hide unrelated images', () async {
    setup();
    workspace.write(
      'lib/main.dart',
      'const values = [1, 2, 3]; void main() { print(values); }',
    );
    expect((await analyze()).findings, hasLength(5));
  });

  test(
    'only-density images, nested registration, duplicates and an empty directory',
    () async {
      workspace.write('pubspec.yaml', '''
name: runner_fixture
flutter:
  assets:
    - assets/
    - assets/images/
    - assets/images/logo.png
    - assets/empty/
''');
      workspace.write('assets/2.0x/only.png', 'image');
      workspace.write('assets/images/3.0x/logo.png', 'image');
      Directory(
        p.join(workspace.path, 'assets/empty'),
      ).createSync(recursive: true);
      workspace.write('lib/main.dart', 'void main() {}');
      expect(unused(await analyze()), {
        "Unused asset 'assets/only.png'.",
        "Unused asset 'assets/images/logo.png'.",
      });
    },
  );

  for (final invalid in [
    '  assets: {}',
    '  assets: [42]',
    '  assets: [{path: 42}]',
    '  assets: [../outside.png]',
    '  assets: [missing/]',
    '  fonts: {}',
    '  fonts: [42]',
    '  fonts: [{family: 42}]',
    '  fonts: [{family: "", fonts: [{asset: font.ttf}]}]',
    '  fonts: [{family: Example}]',
    '  fonts: [{family: Example, fonts: []}]',
    '  fonts: [{family: Example, fonts: [42]}]',
    '  fonts: [{family: Example, fonts: [{asset: 42}]}]',
    '  fonts: [{family: Example, fonts: [{asset: ../outside.ttf}]}]',
  ]) {
    test('invalid asset/font schema fails closed: $invalid', () async {
      workspace.write(
        'pubspec.yaml',
        'name: runner_fixture\nflutter:\n$invalid\n',
      );
      workspace.write('lib/main.dart', 'void main() {}');
      expect(analyze(), throwsA(isA<ResolvedAnalysisException>()));
      expect((await analyze(rules: {RuleId.unusedFile})).findings, isEmpty);
    });
  }

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
