// The imports are intentionally loaded only through their deferred prefixes.
// ignore_for_file: unused_import

import 'dart:io';

import 'package:kareki/kareki.dart' deferred as coverage00;
import 'package:kareki/src/baseline/baseline.dart' deferred as coverage01;
import 'package:kareki/src/cli/cli.dart' deferred as coverage02;
import 'package:kareki/src/cli/doctor_cli.dart' deferred as coverage03;
import 'package:kareki/src/config/kareki_config.dart' deferred as coverage04;
import 'package:kareki/src/dependency/pub_dependency_checker.dart'
    deferred as coverage05;
import 'package:kareki/src/doctor/doctor_finding.dart' deferred as coverage06;
import 'package:kareki/src/doctor/doctor_reporter.dart' deferred as coverage07;
import 'package:kareki/src/doctor/doctor_runner.dart' deferred as coverage08;
import 'package:kareki/src/entry_points/entry_point_resolver.dart'
    deferred as coverage09;
import 'package:kareki/src/model/declaration.dart' deferred as coverage10;
import 'package:kareki/src/model/finding.dart' deferred as coverage11;
import 'package:kareki/src/model/package_info.dart' deferred as coverage12;
import 'package:kareki/src/parser/declaration_collector.dart'
    deferred as coverage13;
import 'package:kareki/src/preset/builtin_presets.dart' deferred as coverage14;
import 'package:kareki/src/preset/preset.dart' deferred as coverage15;
import 'package:kareki/src/preset/preset_registry.dart' deferred as coverage16;
import 'package:kareki/src/reachability/reachability_graph.dart'
    deferred as coverage17;
import 'package:kareki/src/reachability/unused_file_detector.dart'
    deferred as coverage18;
import 'package:kareki/src/reporter/reporter.dart' deferred as coverage19;
import 'package:kareki/src/runner.dart' deferred as coverage20;
import 'package:kareki/src/workspace/workspace_loader.dart'
    deferred as coverage21;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('coverage loads every Dart library under lib', () async {
    final libDirectory = Directory(p.join(Directory.current.path, 'lib'));
    final expectedLibraries = libDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.dart')
        .map(
          (file) => p
              .relative(file.path, from: libDirectory.path)
              .split(p.separator)
              .join('/'),
        )
        .toSet();

    final source = File(
      p.join('test', 'all_lib_files_coverage_test.dart'),
    ).readAsStringSync();
    final importedLibraries = RegExp(
      r"^import 'package:kareki/([^']+)'(?:\s+)deferred as coverage\d+;",
      multiLine: true,
    ).allMatches(source).map((match) => match.group(1)!).toSet();

    expect(
      importedLibraries,
      expectedLibraries,
      reason:
          'Keep the deferred imports in this test in sync with lib/**.dart '
          'so an untested library is still included in coverage.',
    );

    await Future.wait([
      coverage00.loadLibrary(),
      coverage01.loadLibrary(),
      coverage02.loadLibrary(),
      coverage03.loadLibrary(),
      coverage04.loadLibrary(),
      coverage05.loadLibrary(),
      coverage06.loadLibrary(),
      coverage07.loadLibrary(),
      coverage08.loadLibrary(),
      coverage09.loadLibrary(),
      coverage10.loadLibrary(),
      coverage11.loadLibrary(),
      coverage12.loadLibrary(),
      coverage13.loadLibrary(),
      coverage14.loadLibrary(),
      coverage15.loadLibrary(),
      coverage16.loadLibrary(),
      coverage17.loadLibrary(),
      coverage18.loadLibrary(),
      coverage19.loadLibrary(),
      coverage20.loadLibrary(),
      coverage21.loadLibrary(),
    ]);
  });
}
