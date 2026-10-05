import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/resolved_analysis/conditional_probe.dart';
import '../../tool/resolved_analysis/probe.dart';
import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_conditional_probe_');
    workspace.writePubspec(name: 'app');
    workspace.write(
      '.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'app',
            'rootUri': Uri.directory(workspace.path).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
        ],
      }),
    );
    workspace.write('lib/stub.dart', 'void platform() {}');
    workspace.write('lib/io.dart', 'void platform() {}');
    workspace.write('lib/web.dart', 'void platform() {}');
  });
  tearDown(() => workspace.dispose());

  Future<ProbeSnapshot> resolve(
    ConditionalSourceOverlay overlay, {
    List<String>? files,
  }) => resolveProbe(
    includedPaths: [workspace.path],
    files: (files ?? ['lib/api.dart'])
        .map((file) => p.join(workspace.path, file))
        .toList(),
    resourceProvider: overlay,
  );
  Set<String> targets(ProbeSnapshot snapshot) => snapshot.references
      .where((reference) => reference.spelling == 'platform')
      .map((reference) => p.basename(reference.target!.unitPath))
      .toSet();

  test(
    'body syntax is validated using the owning package language version',
    () async {
      workspace.write(
        'lib/api.dart',
        "import 'stub.dart' if (dart.library.html) 'web.dart'; void run(final int value) => platform();",
      );
      final overlay = ConditionalSourceOverlay(
        conditionalProbeProfiles['web-js']!,
      );
      final snapshot = await resolve(overlay);
      expect(targets(snapshot), {'web.dart'});
      expect(snapshot.diagnostics.where((d) => d.severity == 'ERROR'), isEmpty);
      expect(overlay.issues, isEmpty);
    },
  );

  test('malformed conditional directives are never rewritten', () {
    const source = "import 'stub.dart' if (dart.library.html 'web.dart';";
    final path = p.join(workspace.path, 'lib/api.dart');
    workspace.write('lib/api.dart', source);
    final overlay = ConditionalSourceOverlay(
      conditionalProbeProfiles['web-js']!,
    );
    expect(overlay.getFile(path).readAsStringSync(), source);
    expect(overlay.issues, isNotEmpty);
    expect(overlay.selections, isEmpty);
  });

  test(
    'all candidate profiles rebind the same call without writing source',
    () async {
      const source =
          "import 'stub.dart' if (dart.library.io) 'io.dart' if (dart.library.html) 'web.dart';\nvoid run() => platform();\n";
      workspace.write('lib/api.dart', source);
      final offsets = <int>{};
      for (final profile in conditionalProbeProfiles.entries) {
        final overlay = ConditionalSourceOverlay(profile.value);
        final snapshot = await resolve(overlay);
        expect(
          snapshot.diagnostics.where((d) => d.severity == 'ERROR'),
          isEmpty,
        );
        expect(overlay.issues, isEmpty);
        expect(targets(snapshot), {
          switch (profile.key) {
            'native' => 'io.dart',
            'web-js' => 'web.dart',
            _ => 'stub.dart',
          },
        });
        offsets.add(
          snapshot.references
              .singleWhere((r) => r.spelling == 'platform')
              .offset,
        );
        expect(
          File(p.join(workspace.path, 'lib/api.dart')).readAsStringSync(),
          source,
        );
      }
      expect(offsets, {source.indexOf('platform();')});
    },
  );

  test(
    'exports prefixes combinators unicode and CRLF preserve declaration IDs',
    () async {
      const source =
          "/// 😀\r\nexport 'stub.dart'\r\n if (dart.library.html) 'web.dart' show platform;\r\nvoid same() {}\r\n";
      workspace.write('lib/api.dart', source);
      workspace.write(
        'lib/client.dart',
        "import 'api.dart' as chosen; void run() => chosen.platform();",
      );
      final ids = <ProbeId>{};
      for (final name in ['native', 'web-js']) {
        final overlay = ConditionalSourceOverlay(
          conditionalProbeProfiles[name]!,
        );
        final snapshot = await resolve(
          overlay,
          files: ['lib/api.dart', 'lib/client.dart'],
        );
        expect(targets(snapshot), {
          if (name == 'native') 'stub.dart' else 'web.dart',
        });
        ids.add(
          snapshot.declarations.values.singleWhere((d) => d.label == 'same').id,
        );
        final virtual = overlay
            .getFile(p.join(workspace.path, 'lib/api.dart'))
            .readAsStringSync();
        expect(virtual.length, source.length);
        expect(virtual.indexOf('void same'), source.indexOf('void same'));
        expect(
          '\r\n'.allMatches(virtual).map((m) => m.start),
          '\r\n'.allMatches(source).map((m) => m.start),
        );
      }
      expect(ids, hasLength(1));
    },
  );

  test(
    'first matching condition wins, including explicit string comparisons',
    () async {
      workspace.write(
        'lib/api.dart',
        "import 'stub.dart' if (flavor == 'blue') 'io.dart' if (other) 'web.dart'; void run() => platform();",
      );
      expect(
        targets(
          await resolve(
            ConditionalSourceOverlay({'flavor': 'blue', 'other': 'true'}),
          ),
        ),
        {'io.dart'},
      );
      expect(
        targets(
          await resolve(
            ConditionalSourceOverlay({'flavor': 'red', 'other': 'true'}),
          ),
        ),
        {'web.dart'},
      );
    },
  );

  test(
    'unspecified conditions stay intact and explicitly prevent coverage claims',
    () async {
      const source =
          "import 'stub.dart' if (app.custom) 'web.dart'; void run() => platform();";
      workspace.write('lib/api.dart', source);
      final overlay = ConditionalSourceOverlay(
        conditionalProbeProfiles['native']!,
      );
      await resolve(overlay);
      expect(
        overlay.issues.single,
        contains('unspecified conditions app.custom'),
      );
      expect(
        overlay
            .getFile(p.join(workspace.path, 'lib/api.dart'))
            .readAsStringSync(),
        source,
      );
      expect(overlay.selections, isEmpty);
    },
  );

  test(
    'transitive conditional exports are selected in the same profile',
    () async {
      workspace.write(
        'lib/api.dart',
        "import 'facade.dart'; void run() => platform();",
      );
      workspace.write(
        'lib/facade.dart',
        "export 'stub.dart' if (dart.library.html) 'web.dart';",
      );
      final overlay = ConditionalSourceOverlay(
        conditionalProbeProfiles['web-js']!,
      );
      expect(targets(await resolve(overlay)), {'web.dart'});
      expect(
        overlay.selections.any((s) => s.path.endsWith('facade.dart')),
        isTrue,
      );
    },
  );

  test('dependency package conditional exports are also selected', () async {
    final config = File(
      p.join(workspace.path, '.dart_tool/package_config.json'),
    );
    final parsed =
        jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
    (parsed['packages'] as List<dynamic>).add({
      'name': 'dependency',
      'rootUri': Uri.directory(p.join(workspace.path, 'dependency')).toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.10',
    });
    workspace.write('.dart_tool/package_config.json', jsonEncode(parsed));
    workspace.write(
      'dependency/lib/api.dart',
      "export 'default.dart' if (dart.library.html) 'browser.dart';",
    );
    workspace.write('dependency/lib/default.dart', 'void platform() {}');
    workspace.write('dependency/lib/browser.dart', 'void platform() {}');
    workspace.write(
      'lib/api.dart',
      "import 'package:dependency/api.dart'; void run() => platform();",
    );
    final overlay = ConditionalSourceOverlay(
      conditionalProbeProfiles['web-js']!,
    );
    expect(targets(await resolve(overlay)), {'browser.dart'});
    expect(
      overlay.selections.any((s) => s.path.contains('/dependency/')),
      isTrue,
    );
  });

  test(
    'missing alternate libraries and incompatible APIs are not successes',
    () async {
      workspace.write(
        'lib/api.dart',
        "import 'stub.dart' if (dart.library.html) 'missing.dart'; void run() => platform();",
      );
      final missing = await resolve(
        ConditionalSourceOverlay(conditionalProbeProfiles['web-js']!),
      );
      expect(
        missing.diagnostics.where((d) => d.severity == 'ERROR'),
        isNotEmpty,
      );
      workspace.write('lib/missing.dart', 'void platform(int required) {}');
      final mismatch = await resolve(
        ConditionalSourceOverlay(conditionalProbeProfiles['web-js']!),
      );
      expect(
        mismatch.diagnostics.where((d) => d.severity == 'ERROR'),
        isNotEmpty,
      );
    },
  );

  test(
    'analyzer-excluded inputs remain accessible in the owning context',
    () async {
      workspace.write(
        'analysis_options.yaml',
        'analyzer:\n  exclude:\n    - lib/api.dart\n',
      );
      workspace.write(
        'lib/api.dart',
        "import 'stub.dart' if (dart.library.html) 'web.dart'; void run() => platform();",
      );
      expect(
        targets(
          await resolve(
            ConditionalSourceOverlay(conditionalProbeProfiles['web-js']!),
          ),
        ),
        {'web.dart'},
      );
    },
  );

  test('new overlays read changed sources without old selection state', () async {
    workspace.write(
      'lib/api.dart',
      "import 'stub.dart' if (dart.library.html) 'web.dart'; void run() => platform();",
    );
    expect(
      targets(
        await resolve(
          ConditionalSourceOverlay(conditionalProbeProfiles['web-js']!),
        ),
      ),
      {'web.dart'},
    );
    workspace.write(
      'lib/api.dart',
      "import 'stub.dart' if (dart.library.html) 'io.dart'; void run() => platform();",
    );
    expect(
      targets(
        await resolve(
          ConditionalSourceOverlay(conditionalProbeProfiles['web-js']!),
        ),
      ),
      {'io.dart'},
    );
  });
}
