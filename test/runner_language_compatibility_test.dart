import 'dart:io';

import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void _write(String root, String path, String contents) {
  final file = File(p.join(root, path));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('kareki_language_');
    _write(workspace.path, 'pubspec.yaml', '''
name: language_workspace
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
workspace:
  - app
''');
    _write(workspace.path, 'app/pubspec.yaml', '''
name: app
publish_to: none
environment:
  sdk: ">=3.10.0 <4.0.0"
resolution: workspace
''');
  });

  tearDown(() {
    if (workspace.existsSync()) workspace.deleteSync(recursive: true);
  });

  test('Dart 3.10-3.12 syntax keeps used APIs reachable', () {
    _write(workspace.path, 'app/lib/api.dart', '''
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
    _write(workspace.path, 'app/bin/main.dart', '''
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
}
