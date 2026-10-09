import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() => workspace = TestWorkspace.create('kareki_build_deps_'));
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze({bool strict = false}) => KarekiRunner().analyze(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: {RuleId.unusedPubDependency},
      strictDependencies: strict,
    ),
  );

  test(
    'options includes follow relative, package and transitive references',
    () async {
      workspace.writePubspec(
        name: 'app',
        dependencies: {'rules', 'unused'},
        devDependencies: {'transitive'},
      );
      workspace.write('vendor/rules/pubspec.yaml', 'name: rules\n');
      workspace.write('vendor/transitive/pubspec.yaml', 'name: transitive\n');
      workspace.write(
        'analysis_options.yaml',
        'include: config/options.yaml\n',
      );
      workspace.write(
        'config/options.yaml',
        'include: package:rules/options.yaml\n',
      );
      workspace.write(
        'vendor/rules/lib/options.yaml',
        'include: package:transitive/options.yaml\n',
      );
      workspace.write(
        'vendor/transitive/lib/options.yaml',
        'include: package:rules/options.yaml\n',
      );
      workspace.write('lib/main.dart', 'void main() {}');
      final result = await analyze(strict: true);
      expect(result.findings.map((f) => f.stableId), ['pubdep|app|unused']);
    },
  );

  test(
    'resolved icon font use is package-scoped and works in dependency-only runs',
    () async {
      workspace.writePubspec(
        name: 'app',
        dependencies: {'flutter', 'font_assets', 'unused_font'},
      );
      workspace.write('vendor/flutter/pubspec.yaml', 'name: flutter\n');
      workspace.write('vendor/flutter/lib/src/widgets/icon_data.dart', '''
class IconData {
  const IconData(int code, {this.fontPackage});
  final String? fontPackage;
}
''');
      workspace.write('vendor/flutter/lib/widgets.dart', '''
export 'src/widgets/icon_data.dart';
import 'src/widgets/icon_data.dart';
class Icons { static const add = IconData(1, fontPackage: 'font_assets'); }
''');
      workspace.write('lib/main.dart', '''
import 'package:flutter/widgets.dart';
class IconData { const IconData({String? fontPackage}); }
void main() { print(Icons.add); print(const IconData(fontPackage: 'unused_font')); }
''');
      final result = await analyze();
      expect(result.findings.map((f) => f.stableId), [
        'pubdep|app|unused_font',
      ]);
      workspace.write('lib/main.dart', '''
import 'package:flutter/widgets.dart';
void main() { print(const IconData(2, fontPackage: 'font_assets')); }
''');
      expect((await analyze()).findings.map((f) => f.stableId), [
        'pubdep|app|unused_font',
      ]);
      workspace.write('lib/main.dart', 'void main() {}');
      expect((await analyze()).findings.map((f) => f.stableId), [
        'pubdep|app|font_assets',
        'pubdep|app|unused_font',
      ]);
    },
  );
}
