import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/workspace/workspace_loader.dart';
import 'package:path/path.dart' as p;

/// Checks public analyzer APIs on an excluded source without changing options.
/// Usage: `dart tool/resolved_analysis/excluded_context_probe.dart ROOT FILE`
Future<void> main(List<String> arguments) async {
  final root = Directory(arguments[0]).resolveSymbolicLinksSync();
  final file = File(arguments[1]).resolveSymbolicLinksSync();
  final config = KarekiConfig.load(root);
  final packages = WorkspaceLoader(
    rootPath: root,
  ).load(include: config.includePackages, exclude: config.excludePackages);
  final collection = AnalysisContextCollection(
    includedPaths: packages.map((package) => package.rootPath).toList(),
  );
  final report = <String, Object?>{'contexts': collection.contexts.length};
  try {
    try {
      collection.contextFor(file);
      report['contextFor'] = 'accepted';
    } on Object catch (error) {
      report['contextFor'] = error.toString();
    }
    final candidates =
        collection.contexts.where((context) {
          final contextPath = context.contextRoot.root.path;
          return contextPath == file || p.isWithin(contextPath, file);
        }).toList()..sort(
          (a, b) => b.contextRoot.root.path.length.compareTo(
            a.contextRoot.root.path.length,
          ),
        );
    report['enclosingContexts'] = candidates.length;
    if (candidates.isNotEmpty) {
      final selected = candidates.first;
      report['selectedRoot'] = selected.contextRoot.root.path;
      final result = await selected.currentSession.getResolvedUnit(file);
      report['resolved'] = result is ResolvedUnitResult && result.exists;
      if (result is ResolvedUnitResult) {
        report['errors'] = [
          for (final diagnostic in result.diagnostics)
            if (diagnostic.diagnosticCode.severity.name == 'ERROR')
              diagnostic.message,
        ];
      }
    }
  } finally {
    await collection.dispose();
  }
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
