import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';

/// Detects packages declared in `pubspec.yaml` that are never imported.
///
/// The check subtracts from the declared set:
/// - packages actually imported by source,
/// - packages implied by annotations used in source (via the merged
///   preset registry passed as `annotationImpliedPackages`),
/// - packages explicitly suppressed via `ignoredDeps`,
/// - `sdkPackages` (Flutter / Dart SDK packages).
class PubDependencyChecker {
  List<Finding> check({
    required PackageInfo package,
    required Iterable<ParsedFile> filesInPackage,
    required Map<String, Set<String>> annotationImpliedPackages,
    required Set<String> sdkPackages,
    Set<String> ignoredDeps = const {},
    bool strict = false,
  }) {
    final imported = <String>{};
    final implicitlyNeeded = <String>{};
    for (final file in filesInPackage) {
      for (final uri in [...file.imports, ...file.exports]) {
        final pkg = _packageFromUri(uri);
        if (pkg != null) imported.add(pkg);
      }
      for (final decl in file.declarations) {
        for (final annotation in decl.annotations) {
          final implied = annotationImpliedPackages[annotation];
          if (implied != null) implicitlyNeeded.addAll(implied);
        }
      }
    }

    // proto-generated files reference fixnum / protobuf for Int64 etc.
    // Detect protobuf usage by the presence of any .pb.dart file in the
    // package (those files are typically excluded from analysis but still
    // visible to the file iterator).
    final usesProtoGenerated = filesInPackage.any(
      (f) =>
          f.path.endsWith('.pb.dart') ||
          f.path.endsWith('.pbenum.dart') ||
          f.path.endsWith('.pbjson.dart'),
    );
    if (usesProtoGenerated) {
      implicitlyNeeded.addAll({'protobuf', 'fixnum'});
    }

    final declared = <String>{
      ...package.dependencies,
      if (strict) ...package.devDependencies,
    };

    final unused = declared
        .difference(imported)
        .difference(implicitlyNeeded)
        .difference(ignoredDeps)
        .difference(sdkPackages);
    return [
      for (final pkg in unused.toList()..sort())
        Finding(
          ruleId: RuleId.unusedPubDependency,
          severity: Severity.warning,
          message:
              "Dependency '$pkg' is declared in pubspec.yaml but never "
              "imported within '${package.name}'.",
          packageName: package.name,
          filePath: package.pubspecPath,
          line: 1,
          column: 1,
          length: 0,
          stableId: 'pubdep|${package.name}|$pkg',
        ),
    ];
  }

  String? _packageFromUri(String uri) {
    if (!uri.startsWith('package:')) return null;
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(0, slash);
  }
}
