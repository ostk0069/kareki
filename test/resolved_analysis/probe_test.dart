import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/resolved_analysis/probe.dart';
import '../support/test_workspace.dart';

void main() {
  for (final sharedConfig in [true, false]) {
    group(sharedConfig ? 'pub workspace' : 'separate package contexts', () {
      late _Fixture fixture;
      late ProbeSnapshot snapshot;

      setUpAll(() async {
        fixture = _Fixture(sharedConfig: sharedConfig);
        snapshot = await fixture.resolve();
      });

      tearDownAll(() => fixture.dispose());

      test('fixture resolves cleanly in the expected contexts', () {
        expect(snapshot.unresolvedFiles, isEmpty);
        expect(
          snapshot.diagnostics.where((d) => d.severity == 'ERROR'),
          isEmpty,
          reason: snapshot.diagnostics.map((d) => d.code).join(', '),
        );
        expect(snapshot.contextRoots.length, sharedConfig ? 1 : 3);
      });

      test('same-name methods bind only to the referenced class', () {
        final used = fixture.declaration(snapshot, 'alpha', 'Store.save');
        final unused = fixture.declaration(snapshot, 'beta', 'Store.save');
        expect(used, isNot(unused));
        expect(fixture.targets(snapshot, 'save'), contains(used));
        expect(fixture.targets(snapshot, 'save'), isNot(contains(unused)));
        final sibling = fixture.declaration(
          snapshot,
          'alpha',
          'Unrelated.save',
        );
        expect(used.unitPath, sibling.unitPath);
        expect(used, isNot(sibling));
        expect(fixture.targets(snapshot, 'save'), isNot(contains(sibling)));
      });

      test('re-export and prefix preserve cross-package function identity', () {
        final used = fixture.declaration(snapshot, 'alpha', 'save');
        final unused = fixture.declaration(snapshot, 'beta', 'save');
        expect(fixture.targets(snapshot, 'save'), contains(used));
        expect(fixture.targets(snapshot, 'save'), isNot(contains(unused)));
      });

      test('same-name classes have distinct type references', () {
        final alpha = fixture.declaration(snapshot, 'alpha', 'Store');
        final beta = fixture.declaration(snapshot, 'beta', 'Store');
        expect(alpha, isNot(beta));
        expect(fixture.targets(snapshot, 'Store'), containsAll([alpha, beta]));
      });

      test('generic specializations normalize to the original method', () {
        final echo = fixture.declaration(snapshot, 'alpha', 'Box.echo');
        final calls = fixture.targets(snapshot, 'echo').toList();
        expect(calls, hasLength(2));
        expect(calls.toSet(), {echo});
      });

      test(
        'field accessors normalize but explicit accessors stay distinct',
        () {
          final field = fixture.declaration(snapshot, 'alpha', 'Props.count');
          final getter = fixture.declaration(snapshot, 'alpha', 'Props.value');
          final setter = fixture.declaration(snapshot, 'alpha', 'Props.value=');
          expect(getter, isNot(setter));
          expect(fixture.targets(snapshot, 'count').toSet(), {field});
          expect(
            fixture.targets(snapshot, 'value'),
            containsAll([getter, setter]),
          );
        },
      );

      test('named and unnamed constructors match their declarations', () {
        final named = fixture.declaration(snapshot, 'alpha', 'Store.named');
        final unnamed = fixture.declaration(snapshot, 'alpha', 'Store.new');
        expect(named, isNot(unnamed));
        expect(fixture.targets(snapshot, 'a.Store.named'), contains(named));
        expect(fixture.targets(snapshot, 'a.Store'), contains(unnamed));
      });

      test(
        'implicit constructors retain identity without an AST declaration',
        () {
          final target = fixture.targets(snapshot, 'a.Props').single!;
          expect(target.kind, 'CONSTRUCTOR');
          expect(
            target,
            isNot(fixture.declaration(snapshot, 'alpha', 'Props')),
          );
          expect(snapshot.declarations.containsKey(target), isFalse);
        },
      );

      test('compound writes reference both explicit accessors', () {
        final getter = fixture.declaration(snapshot, 'alpha', 'Props.value');
        final setter = fixture.declaration(snapshot, 'alpha', 'Props.value=');
        for (final expression in ['value +=', 'value++;', 'value; // prefix']) {
          final offset = _app.indexOf(expression);
          expect(offset, greaterThanOrEqualTo(0));
          final targets = snapshot.references
              .where((r) => r.path == fixture.appPath && r.offset == offset)
              .map((r) => r.target)
              .toSet();
          expect(targets, {getter, setter}, reason: expression);
        }
      });

      test('part declarations use their physical unit and owning library', () {
        final target = fixture.declaration(snapshot, 'alpha', 'partValue');
        expect(target.unitPath, endsWith('model_part.dart'));
        expect(target.libraryPath, endsWith('model.dart'));
        expect(fixture.targets(snapshot, 'partValue'), contains(target));
      });

      test('extension dispatch resolves to the extension member', () {
        final target = fixture.declaration(snapshot, 'alpha', 'Tag.tag');
        expect(fixture.targets(snapshot, 'tag'), contains(target));
      });

      test('a local shadow is not a reference to the top-level homonym', () {
        final localCall = snapshot.references.singleWhere(
          (r) =>
              r.path == fixture.appPath &&
              r.offset == _app.indexOf('save();\n}'),
        );
        final local = localCall.target;
        expect(local, isNotNull);
        expect(local!.unitPath, fixture.appPath);
        expect(local.offset, _app.indexOf('save() {}'));
        final calls = snapshot.references.where(
          (r) => r.path == fixture.appPath && r.spelling == 'save',
        );
        expect(calls.where((r) => r.target == local), hasLength(1));
        expect(local, isNot(fixture.declaration(snapshot, 'alpha', 'save')));
      });

      test('generated-file references retain the correct target and owner', () {
        final used = fixture.declaration(snapshot, 'alpha', 'Store.save');
        final caller = fixture.declaration(snapshot, 'app', 'generatedCall');
        final reference = snapshot.references.singleWhere(
          (r) => r.path.endsWith('client.g.dart') && r.spelling == 'save',
        );
        expect(reference.target, used);
        expect(reference.owner, caller);
      });

      test('virtual calls expose the contract, not all implementations', () {
        final contract = fixture.declaration(
          snapshot,
          'alpha',
          'Contract.save',
        );
        final implementation = fixture.declaration(
          snapshot,
          'alpha',
          'Implementation.save',
        );
        final call = snapshot.references.singleWhere(
          (r) =>
              r.path == fixture.appPath &&
              r.offset == _app.indexOf('save(); // virtual'),
        );
        expect(call.target, contract);
        expect(call.target, isNot(implementation));
      });

      test(
        'IDs survive a new analysis collection and reversed file order',
        () async {
          final second = await fixture.resolve(reverse: true);
          expect(
            second.declarations.keys.toSet(),
            snapshot.declarations.keys.toSet(),
          );
          expect(
            second.references.map((r) => (r.path, r.offset, r.target)).toSet(),
            snapshot.references
                .map((r) => (r.path, r.offset, r.target))
                .toSet(),
          );
        },
      );
    });
  }

  test('dynamic and invalid references remain explicitly unresolved', () async {
    final fixture = _Fixture(sharedConfig: true);
    addTearDown(fixture.dispose);
    fixture.workspace.write('packages/app/lib/unresolved.dart', '''
import 'package:missing/missing.dart';
void unknown(dynamic object) {
  object.save();
  missingFunction();
}
''');
    final file = fixture.path('app', 'lib/unresolved.dart');
    final snapshot = await fixture.resolve(extraFiles: [file]);
    expect(snapshot.diagnostics.any((d) => d.severity == 'ERROR'), isTrue);
    final unknowns = snapshot.references.where(
      (r) => r.path == file && {'save', 'missingFunction'}.contains(r.spelling),
    );
    expect(unknowns, hasLength(2));
    expect(unknowns.every((r) => r.target == null), isTrue);
    expect(
      fixture.targets(snapshot, 'save'),
      contains(fixture.declaration(snapshot, 'alpha', 'Store.save')),
    );
  });

  test(
    'a dynamic call can be unresolved even without analyzer errors',
    () async {
      final fixture = _Fixture(sharedConfig: true);
      addTearDown(fixture.dispose);
      fixture.workspace.write('packages/app/lib/dynamic.dart', '''
void invokeDynamic(dynamic object) => object.save();
''');
      final file = fixture.path('app', 'lib/dynamic.dart');
      final snapshot = await fixture.resolve(extraFiles: [file]);
      expect(snapshot.diagnostics.where((d) => d.severity == 'ERROR'), isEmpty);
      expect(
        snapshot.references
            .singleWhere((r) => r.path == file && r.spelling == 'save')
            .target,
        isNull,
      );
    },
  );

  test('syntax errors are visible while valid units still resolve', () async {
    final fixture = _Fixture(sharedConfig: true);
    addTearDown(fixture.dispose);
    fixture.workspace.write('packages/app/lib/broken.dart', 'class Broken {');
    final file = fixture.path('app', 'lib/broken.dart');
    final snapshot = await fixture.resolve(extraFiles: [file]);
    expect(
      snapshot.diagnostics.where(
        (d) => d.path == file && d.severity == 'ERROR',
      ),
      isNotEmpty,
    );
    expect(
      fixture.targets(snapshot, 'save'),
      contains(fixture.declaration(snapshot, 'alpha', 'Store.save')),
    );
  });

  test(
    'missing package configuration does not yield fake resolved IDs',
    () async {
      final fixture = _Fixture(sharedConfig: false, writePackageConfig: false);
      addTearDown(fixture.dispose);
      final snapshot = await fixture.resolve();
      expect(
        snapshot.diagnostics.any((d) => d.code == 'uri_does_not_exist'),
        isTrue,
      );
      final call = snapshot.references.singleWhere(
        (r) => r.path == fixture.appPath && r.offset == _app.indexOf('save();'),
      );
      expect(call.target, isNull);
    },
  );
}

class _Fixture {
  _Fixture({required this.sharedConfig, bool writePackageConfig = true}) {
    workspace = TestWorkspace.create('kareki_resolved_probe_');
    // Match analyzer's physical paths on platforms where /tmp is a symlink.
    root = workspace.directory.resolveSymbolicLinksSync();
    workspace.write('pubspec.yaml', '''
name: probe_workspace
environment:
  sdk: '>=3.10.0 <4.0.0'
${sharedConfig ? 'workspace: [packages/app, packages/alpha, packages/beta]' : ''}
''');
    for (final name in ['app', 'alpha', 'beta']) {
      workspace.write('packages/$name/pubspec.yaml', '''
name: $name
environment:
  sdk: '>=3.10.0 <4.0.0'
${sharedConfig ? 'resolution: workspace' : ''}
${name == 'app' ? 'dependencies:\n  alpha:\n    path: ../alpha\n  beta:\n    path: ../beta' : ''}
''');
    }
    // Deterministic, network-free configurations equivalent to pub get for
    // these dependency-free fixtures. This is test setup, not a production
    // fallback for missing package_config.json files.
    final config = jsonEncode({
      'configVersion': 2,
      'packages': [
        for (final name in ['app', 'alpha', 'beta'])
          {
            'name': name,
            'rootUri': Uri.directory(path(name, '')).toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
      ],
    });
    if (sharedConfig && writePackageConfig) {
      workspace.write('.dart_tool/package_config.json', config);
    } else if (writePackageConfig) {
      for (final name in ['app', 'alpha', 'beta']) {
        workspace.write(
          'packages/$name/.dart_tool/package_config.json',
          config,
        );
      }
    }
    workspace.write(
      'packages/alpha/lib/api.dart',
      "export 'src/model.dart';\n",
    );
    workspace.write('packages/alpha/lib/src/model.dart', _alpha);
    workspace.write('packages/alpha/lib/src/model_part.dart', '''
part of 'model.dart';
String partValue() => 'part';
''');
    workspace.write('packages/beta/lib/api.dart', '''
class Store {
  void save() {}
}
void save() {}
''');
    workspace.write('packages/app/bin/main.dart', _app);
    workspace.write('packages/app/lib/client.g.dart', '''
// GENERATED CODE - DO NOT MODIFY BY HAND
import 'package:alpha/api.dart';
void generatedCall(Store store) => store.save();
''');
  }

  final bool sharedConfig;
  late final TestWorkspace workspace;
  late final String root;

  String path(String package, String relative) =>
      p.join(root, 'packages', package, relative);

  String get appPath => path('app', 'bin/main.dart');

  Future<ProbeSnapshot> resolve({
    bool reverse = false,
    List<String> extraFiles = const [],
  }) {
    final files = [
      appPath,
      path('app', 'lib/client.g.dart'),
      path('alpha', 'lib/api.dart'),
      path('alpha', 'lib/src/model.dart'),
      path('alpha', 'lib/src/model_part.dart'),
      path('beta', 'lib/api.dart'),
      ...extraFiles,
    ];
    return resolveProbe(
      includedPaths: [root],
      files: reverse ? files.reversed.toList() : files,
    );
  }

  ProbeId declaration(ProbeSnapshot snapshot, String package, String label) =>
      snapshot.declarations.values
          .singleWhere(
            (d) =>
                p.isWithin(path(package, ''), d.id.unitPath) &&
                d.label == label,
          )
          .id;

  Iterable<ProbeId?> targets(ProbeSnapshot snapshot, String spelling) =>
      snapshot.references
          .where((r) => r.path == appPath && r.spelling == spelling)
          .map((r) => r.target);

  void dispose() => workspace.dispose();
}

const _alpha = '''
part 'model_part.dart';
void save() {}
class Store {
  Store();
  Store.named();
  void save() {}
}
class Unrelated {
  void save() {}
}
class Box<T> {
  T echo(T value) => value;
}
class Props {
  int count = 0;
  int get value => count;
  set value(int next) { count = next; }
}
extension Tag on String {
  String tag() => this;
}
abstract class Contract {
  void save();
}
class Implementation implements Contract {
  @override
  void save() {}
}
''';

const _app = '''
import 'package:alpha/api.dart' as a;
import 'package:alpha/api.dart' show Tag;
import 'package:beta/api.dart' as b;
void main() {
  a.Store().save();
  a.Store.named();
  a.save();
  b.Store? other;
  print(other);
  a.Box<int>().echo(1);
  a.Box<String>().echo('text');
  final props = a.Props();
  props.count = 1;
  print(props.count);
  props.value = 2;
  print(props.value);
  props.value += 1;
  props.value++;
  ++props.value; // prefix
  print(a.partValue());
  print('text'.tag());
  invoke(a.Implementation());
  localShadow();
}
void invoke(a.Contract contract) {
  contract.save(); // virtual
}
void localShadow() {
  void save() {}
  save();
}
''';
