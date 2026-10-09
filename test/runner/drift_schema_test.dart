import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/runner.dart';
import 'package:test/test.dart';

import '../support/test_workspace.dart';

void main() {
  late TestWorkspace workspace;

  setUp(() {
    workspace = TestWorkspace.create('kareki_drift_');
    workspace.writePubspec();
    // A resolved dependency fixture, not a name-based annotation exemption.
    workspace.write('vendor/drift/pubspec.yaml', 'name: drift\n');
    workspace.write('vendor/drift/lib/drift.dart', '''
abstract class Table {}
class Column<T> {}
class ColumnBuilder<T> {}
typedef TextColumn = Column<String>;
''');
    workspace.write('lib/schema.dart', '''
import 'package:drift/drift.dart';

TextColumn columnFactory() => TextColumn();
class BaseMessages extends Table {
  TextColumn get inherited => columnFactory();
}
mixin ExtraColumns {
  TextColumn get mixed => columnFactory();
}
class Messages extends BaseMessages with ExtraColumns {
  TextColumn get message => columnFactory();
  late final ColumnBuilder<String> lateColumn = ColumnBuilder<String>();
  static final TextColumn staticColumn = TextColumn();
  String get unrelated => 'unused';
}
class UnusedTable extends Table {
  TextColumn get unusedColumn => TextColumn();
}
''');
    workspace.write('lib/homonym.dart', '''
class Table {}
class Column<T> {}
class Unrelated extends Table {
  Column<String> get message => Column<String>();
}
''');
    workspace.write('bin/main.dart', '''
import '../lib/schema.dart';
import '../lib/homonym.dart';
void main() { print(Messages()); print(Unrelated()); }
''');
  });

  tearDown(() => workspace.dispose());

  Future<List<String>> findings() async => (await KarekiRunner().run(
    RunRequest(
      rootPath: workspace.path,
      config: KarekiConfig.load(workspace.path),
      enabledRules: {RuleId.unusedElement, RuleId.testOnlyUsed},
    ),
  )).findings.map((f) => f.message).toList();

  test('keeps resolved columns, not arbitrary getters or homonyms', () async {
    final messages = await findings();
    for (final name in [
      'Messages.message',
      'Messages.lateColumn',
      'BaseMessages.inherited',
      'ExtraColumns.mixed',
      'columnFactory',
    ]) {
      expect(messages, isNot(contains(contains("'$name'"))));
    }
    for (final name in [
      'Messages.unrelated',
      'Messages.staticColumn',
      'UnusedTable',
      'UnusedTable.unusedColumn',
      'Unrelated.message',
    ]) {
      expect(messages, contains(contains("'$name'")));
    }
  });

  test('disabled or replaced drift preset does not retain columns', () async {
    for (final config in [
      'keep_alive_annotations:\n  presets: [meta]\n',
      'custom_presets:\n  drift:\n    keep_alive_annotations: []\n',
    ]) {
      workspace.write('kareki-config.yaml', config);
      expect(await findings(), contains(contains("'Messages.message'")));
    }
  });

  test('generated overrides do not hide the original schema input', () async {
    workspace.write('lib/schema.g.dart', '''
import 'schema.dart';
import 'package:drift/drift.dart';
class GeneratedMessages extends Messages {
  @override
  TextColumn get message => TextColumn();
}
''');
    expect(await findings(), isNot(contains(contains("'Messages.message'"))));
  });
}
