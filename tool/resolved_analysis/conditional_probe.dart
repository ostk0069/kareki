/// Read-only conditional-binding experiment, not production platform analysis.
library;

import 'dart:convert';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

import 'probe.dart';

/// Candidate conditional URI selections only. The SDK, compiler environment,
/// fromEnvironment constants and runtime platform are NOT changed by this tool.
/// Unspecified variables stay unresolved, rather than being assumed false.
/// These assignments were checked against Flutter 3.41.4's SDK libraries.json
/// (vm, dart2js, wasm). In particular wasm exposes ffi/isolate for conditional
/// imports; availability does not imply their runtime operations are supported.
const conditionalProbeProfiles = <String, Map<String, String>>{
  'native': {
    'dart.library.io': 'true',
    'dart.library.html': 'false',
    'dart.library.js': 'false',
    'dart.library.js_util': 'false',
    'dart.library.js_interop': 'false',
    'dart.library.ffi': 'true',
    'dart.library.isolate': 'true',
  },
  'web-js': {
    'dart.library.io': 'false',
    'dart.library.html': 'true',
    'dart.library.js': 'true',
    'dart.library.js_util': 'true',
    'dart.library.js_interop': 'true',
    'dart.library.ffi': 'false',
    'dart.library.isolate': 'false',
  },
  'web-wasm': {
    'dart.library.io': 'false',
    'dart.library.html': 'false',
    'dart.library.js': 'false',
    'dart.library.js_util': 'false',
    'dart.library.js_interop': 'true',
    'dart.library.ffi': 'true',
    'dart.library.isolate': 'true',
  },
};

/// Tool-only overlay: rewrites conditional URI selection at source-read time,
/// including transitive dependencies, without touching any file on disk.
/// All UTF-16 offsets and line endings are retained. No ASTs are cached here.
class ConditionalSourceOverlay extends OverlayResourceProvider {
  ConditionalSourceOverlay(this.variables)
    : super(PhysicalResourceProvider.INSTANCE);

  final Map<String, String> variables;
  final _seen = <String>{};
  final selections = <({String path, int offset, int line, String uri})>[];
  final issues = <String>{};
  final encounteredVariables = <String>{};

  @override
  File getFile(String path) {
    _prepare(path);
    return super.getFile(path);
  }

  @override
  Resource getResource(String path) {
    _prepare(path);
    return super.getResource(path);
  }

  void _prepare(String path) {
    if (!path.endsWith('.dart') || !_seen.add(path)) return;
    try {
      final file = baseProvider.getFile(path);
      if (!file.exists) return;
      final source = file.readAsStringSync();
      // A valid conditional directive necessarily contains these keywords.
      if (!source.contains('if') ||
          !source.contains('import') && !source.contains('export')) {
        return;
      }
      final result = parseString(
        content: source,
        path: path,
        featureSet: FeatureSet.latestLanguageVersion(),
        throwIfDiagnostics: false,
      );
      final directives = result.unit.directives
          .whereType<NamespaceDirective>()
          .where((directive) => directive.configurations.isNotEmpty)
          .toList();
      if (directives.isEmpty) return;
      // Older parsers can report a missing ')' at EOF, outside the directive
      // diagnostic range. Never rewrite a header recovered with inserted tokens.
      for (final directive in result.unit.directives) {
        // Documentation comments have a separate token chain.
        var token = directive.firstTokenAfterCommentAndMetadata;
        while (true) {
          if (token.isSynthetic) {
            issues.add(
              '$path: recovered directive contains synthetic tokens; no rewrite',
            );
            return;
          }
          if (identical(token, directive.endToken)) break;
          token = token.next!;
        }
      }
      // Only the directive region is used from this standalone parse. Body
      // syntax can belong to an older package language version (for example
      // final parameters). The owning Analyzer session resolves the unchanged
      // body with its package feature set; do not validate it as latest Dart.
      final directiveEnd = result.unit.directives.last.end;
      final parseErrors = result.errors
          .where(
            (error) =>
                error.offset <= directiveEnd &&
                error.diagnosticCode.severity.name == 'ERROR',
          )
          .toList();
      if (parseErrors.isNotEmpty) {
        for (final error in parseErrors) {
          final line = result.lineInfo.getLocation(error.offset).lineNumber;
          issues.add(
            '$path:$line: ${error.diagnosticCode.lowerCaseName}: ${error.message}; no rewrite',
          );
        }
        return;
      }
      final units = source.codeUnits.toList();
      var changed = false;
      for (final directive in directives) {
        final line = result.lineInfo.getLocation(directive.offset).lineNumber;
        final missing = <String>{};
        for (final alternative in directive.configurations) {
          final name = alternative.name.toSource();
          encounteredVariables.add(name);
          if (!variables.containsKey(name)) missing.add(name);
        }
        if (missing.isNotEmpty) {
          issues.add(
            '$path:$line: unspecified conditions ${(missing.toList()..sort()).join(', ')}; no rewrite',
          );
          continue;
        }
        var selected = directive.uri;
        for (final alternative in directive.configurations) {
          final expected = alternative.value?.stringValue ?? 'true';
          if (variables[alternative.name.toSource()] == expected) {
            selected = alternative.uri;
            break;
          }
        }
        final uri = selected.stringValue;
        if (uri == null) {
          issues.add('$path:$line: unknown selected URI; no rewrite');
          continue;
        }
        // Leave the selected literal at its ORIGINAL offset. Blank every other
        // token from the default URI through the final alternative, preserving
        // CR/LF. Prefixes, deferred, show/hide and all later nodes stay in place.
        for (
          var offset = directive.uri.offset;
          offset < directive.configurations.last.end;
          offset++
        ) {
          if (offset >= selected.offset && offset < selected.end) continue;
          if (units[offset] != 10 && units[offset] != 13) units[offset] = 32;
        }
        changed = true;
        selections.add((
          path: path,
          offset: directive.offset,
          line: line,
          uri: uri,
        ));
      }
      if (changed) {
        setOverlay(
          path,
          content: String.fromCharCodes(units),
          modificationStamp: 1,
        );
      }
    } on Object {
      issues.add('$path: source overlay unavailable; no coverage claim');
    }
  }
}

/// Usage: conditional_probe.dart ROOT native|web-js|web-wasm FILE [FILE ...]
/// File names may be relative to ROOT. This tool never removes production warnings.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 3 ||
      !conditionalProbeProfiles.containsKey(arguments[1])) {
    io.stderr.writeln(
      'Usage: conditional_probe.dart ROOT native|web-js|web-wasm FILE [FILE ...]',
    );
    io.exitCode = 64;
    return;
  }
  final root = p.normalize(p.absolute(arguments[0]));
  final files = arguments
      .skip(2)
      .map(
        (file) => p.normalize(p.isAbsolute(file) ? file : p.join(root, file)),
      )
      .toList();
  final overlay = ConditionalSourceOverlay(
    conditionalProbeProfiles[arguments[1]]!,
  );
  final watch = Stopwatch()..start();
  final report = <String, Object?>{
    'profile': arguments[1],
    'variables': overlay.variables,
    'root': root,
    'files': files,
    'scope':
        'conditional URI bindings only; SDK and runtime platform unchanged',
    'canRemoveProductionWarning': false,
    'diagnosticsScope':
        'requested files only; transitive dependency bodies are not audited',
  };
  try {
    final snapshot = await resolveProbe(
      includedPaths: [root],
      files: files,
      resourceProvider: overlay,
    );
    final errors = snapshot.diagnostics
        .where((diagnostic) => diagnostic.severity == 'ERROR')
        .toList();
    report['status'] =
        errors.isEmpty &&
            snapshot.unresolvedFiles.isEmpty &&
            overlay.issues.isEmpty
        ? 'bindings_resolved'
        : 'incomplete';
    report['errors'] = [
      for (final error in errors) {'path': error.path, 'code': error.code},
    ];
    report['unresolvedFiles'] = snapshot.unresolvedFiles;
    report['references'] = [
      for (final reference in snapshot.references)
        if (reference.target case final target?)
          {
            'path': reference.path,
            'offset': reference.offset,
            'name': reference.spelling,
            'targetLibrary': target.libraryPath,
            'targetUnit': target.unitPath,
            'targetOffset': target.offset,
            'targetKind': target.kind,
          },
    ];
  } on Object catch (error) {
    report['status'] = 'failed';
    report['error'] = error.toString();
  }
  report['selections'] = [
    for (final selection in overlay.selections)
      {
        'path': selection.path,
        'offset': selection.offset,
        'line': selection.line,
        'uri': selection.uri,
      },
  ];
  report['issues'] = overlay.issues.toList()..sort();
  report['encounteredVariables'] = overlay.encounteredVariables.toList()
    ..sort();
  report['elapsedMs'] = watch.elapsedMilliseconds;
  if (report['status'] != 'bindings_resolved') io.exitCode = 2;
  io.stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
