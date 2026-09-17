import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_language_');
    workspace.write('pubspec.yaml', '''
name: language_workspace
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - app
''');
    workspace.write('app/pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
resolution: workspace
''');
  });

  tearDown(() => workspace.dispose());

  test('Dart 3.10-3.12 syntax keeps used APIs reachable', () {
    workspace.write('app/lib/api.dart', '''
class Client {
  final String? endpoint;
  Client.named({String? endpoint}) : endpoint = endpoint;
}

Client buildClient() => .named(endpoint: 'localhost');

class Connection {
  final String? host;
  Connection({String? host}) : host = host;
}

Connection buildConnection() => .new(host: 'localhost');

extension type UserId(int value) {
  String format() => value.toString();
}

extension type DeadId(int value) {}

class Point {
  final int _x;
  Point({required this._x});
}
''');
    workspace.write('app/bin/main.dart', '''
import 'package:app/api.dart';

void main() {
  print(buildClient());
  print(buildConnection());
  print(UserId(1).format());
  print(Point(x: 1));
}
''');

    final result = KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );

    for (final parameter in ['endpoint', 'host']) {
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedParameterOptional &&
              finding.message.contains("'$parameter'"),
        ),
        isFalse,
        reason: 'dot shorthand passes $parameter at the constructor call site',
      );
    }
    for (final usedName in [
      'Client',
      'buildClient',
      'Connection',
      'buildConnection',
      'UserId',
      'format',
      'Point',
    ]) {
      expect(
        result.findings.any(
          (finding) =>
              finding.ruleId == RuleId.unusedElement &&
              finding.message.contains("'$usedName'"),
        ),
        isFalse,
        reason: '$usedName is reachable from bin/main.dart',
      );
    }
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'DeadId'"),
      ),
      isTrue,
      reason: 'an unused extension type should still be reported',
    );
  });

  test('Dart 3.13 primary constructors participate in all rules', () {
    workspace.write('app/lib/api.dart', '''
class Point.named(final int usedField, final int unusedField, int unusedInput) {
  int read() => usedField;
}

enum Status({int? code, int? unusedCode}) {
  active(code: 1),
  inactive();
}

Point makePoint() => Point.named(1, 2, 3);
''');
    workspace.write('app/bin/main.dart', '''
import 'package:app/api.dart';

void main() {
  print(makePoint().read());
  print(Status.active);
}
''');

    final result = KarekiRunner().run(
      RunRequest(
        rootPath: workspace.path,
        config: KarekiConfig.load(workspace.path),
      ),
    );

    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'usedField'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedElement &&
            finding.message.contains("'Point.unusedField'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameter &&
            finding.message.contains("'unusedInput'"),
      ),
      isTrue,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'code'"),
      ),
      isFalse,
    );
    expect(
      result.findings.any(
        (finding) =>
            finding.ruleId == RuleId.unusedParameterOptional &&
            finding.message.contains("'unusedCode'"),
      ),
      isTrue,
    );
  });
}
