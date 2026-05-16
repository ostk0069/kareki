import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:path/path.dart' as p;

/// Detects `.dart` files that are not referenced via `import`, `part`, or
/// `export` from any other file in the workspace.
///
/// Entry-point files (passed in `entryPointPaths`) are never reported.
class UnusedFileDetector {
  List<Finding> detect({
    required Iterable<PackageInfo> packages,
    required Iterable<ParsedFile> files,
    required Set<String> entryPointPaths,
  }) {
    final packagesByName = {for (final pkg in packages) pkg.name: pkg};
    final fileList = files.toList();
    final filesByPath = {for (final f in fileList) f.path: f};

    final referenced = <String>{};
    for (final file in fileList) {
      final libraryDir = p.dirname(file.path);
      for (final uri in [...file.imports, ...file.parts, ...file.exports]) {
        final resolved = _resolveUri(
          uri: uri,
          fromDir: libraryDir,
          fromPackage: file.packageName,
          packagesByName: packagesByName,
        );
        if (resolved != null && filesByPath.containsKey(resolved)) {
          referenced.add(resolved);
        }
      }
      // `part of` makes the parent library reference this file's library.
      final partOf = file.partOf;
      if (partOf != null) {
        final resolved = _resolveUri(
          uri: partOf,
          fromDir: libraryDir,
          fromPackage: file.packageName,
          packagesByName: packagesByName,
        );
        if (resolved != null) referenced.add(resolved);
      }
    }

    final findings = <Finding>[];
    for (final file in fileList) {
      if (entryPointPaths.contains(file.path)) continue;
      if (referenced.contains(file.path)) continue;
      findings.add(
        Finding(
          ruleId: RuleId.unusedFile,
          severity: Severity.warning,
          message: 'File is never imported, parted, or exported.',
          packageName: file.packageName,
          filePath: file.path,
          line: 1,
          column: 1,
          length: 0,
          stableId: 'file|${file.packageName}|${file.path}',
        ),
      );
    }
    return findings;
  }

  String? _resolveUri({
    required String uri,
    required String fromDir,
    required String fromPackage,
    required Map<String, PackageInfo> packagesByName,
  }) {
    if (uri.startsWith('dart:')) return null;
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0) return null;
      final pkg = rest.substring(0, slash);
      final path = rest.substring(slash + 1);
      final info = packagesByName[pkg];
      if (info == null) return null;
      return p.normalize(p.join(info.libPath, path));
    }
    // Relative URI.
    return p.normalize(p.join(fromDir, uri));
  }
}
