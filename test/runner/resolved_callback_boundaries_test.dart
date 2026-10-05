import 'dart:async';
import 'dart:convert';

import 'package:kareki/kareki.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

const _api = '''
class Controls {
  void scroll({int duration = 300, int curve = 0}) {}
  Future<void> retry({bool autoPlay = true}) async {}
}
class Badge {
  static int keirin(int label, {int? key, double margin = 0, int size = 20}) => label;
  static int autorace(int label, {int? key, double margin = 0, int size = 20}) => label;
}
T route<T>(T context, Object child, [Object? page, bool barrierDismissible = true]) => context;
typedef Builder = T Function<T>(T context, Object child, Object page);
class Sink {
  Sink(this.scroll, this.retry, this.route);
  final void Function() scroll;
  final Future<void> Function() retry;
  final Builder route;
}
abstract class Sequence {
  Iterable<T> map<T>(T Function(int) callback);
}
''';

const _raw = '''
Sink(c.scroll, c.retry, route);
s.map(Badge.keirin);
s.map(Badge.autorace);
''';

const _bounded = '''
Sink(() => c.scroll(), () => c.retry(),
    <T>(T context, Object child, Object page) => route<T>(context, child, page));
s.map((label) => Badge.keirin(label));
s.map((label) => Badge.autorace(label));
''';

void main() {
  late TestWorkspace workspace;
  setUp(() {
    workspace = TestWorkspace.create('kareki_callback_boundary_');
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
  });
  tearDown(() => workspace.dispose());

  Future<RunResult> analyze(String body) {
    workspace.write(
      'lib/api.dart',
      '$_api\nvoid register(Controls c, Sequence s) { $body }',
    );
    workspace.write('bin/main.dart', 'void main() {}');
    return KarekiRunner().analyze(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
        analysisMode: AnalysisMode.resolved,
        enabledRules: {RuleId.unusedParameterOptional},
      ),
    );
  }

  test(
    'five escaping callbacks become bounded calls without deleting APIs',
    () async {
      final raw = await analyze(_raw);
      expect(raw.analysisWarnings, hasLength(5));
      expect(raw.findings, isEmpty);
      final bounded = await analyze(_bounded);
      expect(bounded.analysisWarnings, isEmpty);
      expect(bounded.findings, hasLength(10));
      expect(
        bounded.findings.any((f) => f.message.contains("'page'")),
        isFalse,
      );
    },
  );

  test('one remaining raw escape still prevents non-use claims', () async {
    final result = await analyze(
      '$_bounded\nfinal escaped = c.scroll; print(escaped);',
    );
    expect(result.analysisWarnings, hasLength(1));
    expect(result.analysisWarnings.single, contains('scroll'));
    expect(result.findings, hasLength(8));
  });

  test(
    'narrow static callback types do not discard runtime parameters',
    () async {
      final result = await analyze('''
void Function() scroll = c.scroll;
Future<void> Function() retry = c.retry;
Builder builder = route;
Sink(scroll, retry, builder);
s.map(Badge.keirin);
s.map(Badge.autorace);
''');
      expect(result.analysisWarnings, hasLength(5));
      expect(result.findings, isEmpty);
    },
  );

  test(
    'direct optional argument uses remain known after adapter boundaries',
    () async {
      final result = await analyze('$_bounded\nc.scroll(duration: 1);');
      expect(result.analysisWarnings, isEmpty);
      expect(result.findings, hasLength(9));
      expect(
        result.findings.any((f) => f.message.contains("'duration'")),
        isFalse,
      );
    },
  );

  test(
    'only a new callable, not a narrower variable type, rejects extra names',
    () {
      var observed = true;
      void original({bool value = true}) {
        observed = value;
      }

      final void Function() raw = original;
      Function.apply(raw, [], {#value: false});
      expect(observed, isFalse);
      // A new closure, not a tear-off, is the boundary under test.
      // ignore: prefer_function_declarations_over_variables, unnecessary_lambdas
      final bounded = () => original();
      expect(
        () => Function.apply(bounded, [], {#value: false}),
        throwsNoSuchMethodError,
      );
      bounded();
      expect(observed, isTrue);
    },
  );

  test('expression adapters preserve the original returned Future', () async {
    final completer = Completer<void>();
    Future<void> original({bool autoPlay = true}) => completer.future;
    // Keep the expression adapter used by Future-returning callbacks.
    // ignore: prefer_function_declarations_over_variables, unnecessary_lambdas
    final bounded = () => original();
    expect(identical(bounded(), completer.future), isTrue);
    completer.complete();
    await bounded();
  });
}
