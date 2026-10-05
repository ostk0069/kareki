import 'dart:io';

import 'package:kareki/kareki.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/reachability/resolved_reachability.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_library_batch_');
    workspace.writePubspec();
    workspace.write('lib/api.dart', '''
part 'first.dart';
part 'second.dart';
void main() { first(); }
''');
    workspace.write('lib/first.dart', '''
part of 'api.dart';
void first() { second(option: 1); }
''');
    workspace.write('lib/second.dart', '''
part of 'api.dart';
void second({int option = 0, int unused = 0}) { print(option + unused); }
void dead() {}
''');
  });
  tearDown(() => workspace.dispose());

  ParsedFile collect(String name) {
    final path = p.join(workspace.path, 'lib', name);
    return DeclarationCollector().collect(
      path: path,
      packageName: 'runner_fixture',
      content: File(path).readAsStringSync(),
    );
  }

  Future<ResolvedReachability> resolve(List<ParsedFile> files) =>
      ResolvedReachability.build(
        files: files,
        generatedPaths: {},
        entryPoints: EntryPointSet(
          entryPointPaths: {p.join(workspace.path, 'lib/api.dart')},
          keepAliveAnnotations: {},
        ),
        config: KarekiConfig.defaults(),
        packageRoots: {'runner_fixture': workspace.path},
        trackArguments: true,
      );

  test(
    'library and part first orders preserve identities and arguments',
    () async {
      final files = [
        collect('api.dart'),
        collect('first.dart'),
        collect('second.dart'),
      ];
      for (final order in [files, files.reversed.toList()]) {
        final result = await resolve(order);
        expect(
          result.reachable.map((d) => d.name),
          unorderedEquals(['main', 'first', 'second']),
        );
        expect(result.productionReachable, result.reachable);
        expect(result.warnings, isEmpty);
        final second = files.last.declarations.first;
        expect(
          result.optionalArgumentStates[second.optionalParameters.first],
          OptionalArgumentState.used,
        );
        expect(
          result.optionalArgumentStates[second.optionalParameters.last],
          OptionalArgumentState.unused,
        );
      }
    },
  );

  test('errors in sibling parts still fail the entire analysis', () async {
    workspace.write(
      'lib/second.dart',
      "part of 'api.dart';\nvoid second({int option = 0}) { missing(); }\n",
    );
    await expectLater(
      resolve([
        collect('api.dart'),
        collect('first.dart'),
        collect('second.dart'),
      ]),
      throwsA(
        isA<ResolvedAnalysisException>().having(
          (e) => e.diagnostics.join(),
          'diagnostics',
          contains('second.dart:2'),
        ),
      ),
    );
  });

  test(
    'units outside the collected scope do not add references or errors',
    () async {
      workspace.write(
        'lib/api.dart',
        "part 'first.dart';\npart 'second.dart';\nvoid main() { first(); missing(); }\n",
      );
      final result = await resolve([
        collect('first.dart'),
        collect('second.dart'),
      ]);
      expect(result.reachable, isEmpty);
      expect(result.warnings, isEmpty);
    },
  );

  test('a disappeared sibling part cannot produce partial findings', () async {
    final files = [
      collect('api.dart'),
      collect('first.dart'),
      collect('second.dart'),
    ];
    File(p.join(workspace.path, 'lib/second.dart')).deleteSync();
    await expectLater(
      resolve(files),
      throwsA(
        isA<ResolvedAnalysisException>().having(
          (e) => e.diagnostics.join(),
          'diagnostics',
          contains('second.dart: no resolved compilation unit'),
        ),
      ),
    );
  });

  test('orphan parts keep unit-level resolution and error checking', () async {
    workspace.write('lib/api.dart', 'void main() {}\n');
    workspace.write(
      'lib/first.dart',
      "part of 'api.dart';\nvoid orphan() {}\n",
    );
    final result = await resolve([collect('first.dart'), collect('api.dart')]);
    expect(result.reachable.map((d) => d.name), ['main']);
    expect(result.warnings, isEmpty);
    workspace.write(
      'lib/first.dart',
      "part of 'api.dart';\nvoid orphan() { missing(); }\n",
    );
    await expectLater(
      resolve([collect('first.dart'), collect('api.dart')]),
      throwsA(
        isA<ResolvedAnalysisException>().having(
          (e) => e.diagnostics.join(),
          'diagnostics',
          contains('first.dart:2'),
        ),
      ),
    );
  });

  test(
    'a part with nested options retains references in its owning context',
    () async {
      workspace.write(
        'lib/api.dart',
        "part 'nested/part.dart';\nvoid main() { first(); }\n",
      );
      workspace.write(
        'lib/nested/analysis_options.yaml',
        'analyzer:\n  exclude: [part.dart]\n',
      );
      workspace.write(
        'lib/nested/part.dart',
        "part of '../api.dart';\nvoid first() {}\n",
      );
      final result = await resolve([
        collect('api.dart'),
        collect('nested/part.dart'),
      ]);
      expect(
        result.reachable.map((d) => d.name),
        unorderedEquals(['main', 'first']),
      );
      expect(result.warnings, isEmpty);
    },
  );
}
