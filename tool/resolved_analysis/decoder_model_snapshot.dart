import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:kareki/src/reachability/external_decoder_models.dart';

/// Prints a resolved dependency closure's fingerprint for manual review only.
/// Usage: dart decoder_model_snapshot.dart SOURCE_FILE LIBRARY_URI
Future<void> main(List<String> args) async {
  final source = File(args[0]).absolute.path;
  final collection = AnalysisContextCollection(includedPaths: [source]);
  try {
    final session = collection.contextFor(source).currentSession;
    final result = await session.getLibraryByUri(args[1]);
    if (result is! LibraryElementResult) throw StateError('$result');
    final snapshot = decoderSourceSnapshot(result.element);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'digest': snapshot.digest,
        'libraries': snapshot.libraries.map((l) => l.uri.toString()).toList()
          ..sort(),
      }),
    );
  } finally {
    await collection.dispose();
  }
}
