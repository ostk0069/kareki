import 'package:glob/glob.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:kareki/src/preset/preset_registry.dart';
import 'package:path/path.dart' as p;

/// Universal Dart / Flutter SDK entry-point conventions.
///
/// Only patterns prescribed by the SDK itself live here. Tool-specific
/// conventions (playbook_flutter `*.story.dart`, widgetbook directories,
/// etc.) are expressed as glob patterns in
/// `KarekiConfig.defaults().entryPointFiles` so projects can opt out by
/// providing their own `entry_points.files` list.
bool _isImplicitEntryPath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  final base = p.basename(path);
  if (base == 'main.dart' || base.startsWith('main_')) return true;
  // Flutter SDK convention — files named `flutter_test_config.dart` next to
  // a test directory are picked up by `flutter test` automatically without
  // being imported.
  if (base == 'flutter_test_config.dart') return true;
  if (base.endsWith('_test.dart') && _containsSegment(normalized, 'test')) {
    return true;
  }
  if (_containsSegment(normalized, 'bin') && base.endsWith('.dart')) {
    return true;
  }
  if (_containsSegment(normalized, 'integration_test') &&
      base.endsWith('.dart')) {
    return true;
  }
  if (normalized.contains('/lib/l10n/')) return true;
  return false;
}

bool _containsSegment(String path, String segment) {
  return path.contains('/$segment/') ||
      path.startsWith('$segment/') ||
      path.endsWith('/$segment');
}

bool _isInTestDir(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return _containsSegment(normalized, 'test');
}

/// Whether [path] belongs to test sources (test/, integration_test/, or
/// any `*_test.dart` / `flutter_test_config.dart` file). Used to split
/// entry points into "production" and "test" buckets so the
/// `test_only_used` rule can flag production declarations that are only
/// referenced from tests.
///
/// [packageRoot] is the absolute path of the file's owning package. It
/// must be supplied so that the check operates on the path relative to
/// the package (otherwise an absolute path like
/// `/.../kareki/test/fixtures/.../lib/foo.dart` would be classified as
/// test source merely because `test` appears somewhere in the prefix).
bool isTestSourcePath(String path, {required String packageRoot}) {
  final base = p.basename(path);
  if (base == 'flutter_test_config.dart') return true;
  if (base.endsWith('_test.dart')) return true;
  final relative = p.relative(path, from: packageRoot).replaceAll(r'\', '/');
  final segments = relative.split('/');
  if (segments.contains('test')) return true;
  if (segments.contains('integration_test')) return true;
  return false;
}

/// Result of resolving entry points across a workspace.
class EntryPointSet {
  EntryPointSet({
    required this.productionRootNames,
    required this.testRootNames,
    required this.entryPointPaths,
    required this.keepAliveAnnotations,
  });

  /// Simple names that seed reachability when only production entry
  /// points (main, bin/, story files, generated code, keep-alive
  /// annotations, ...) are considered.
  final Set<String> productionRootNames;

  /// Simple names contributed exclusively by test entry points
  /// (`*_test.dart`, files under `test/` or `integration_test/`, ...).
  /// A name appearing here but NOT in [productionRootNames] indicates
  /// the symbol is consumed only by tests.
  final Set<String> testRootNames;

  /// Files considered entry points (whose declarations are all reachable
  /// AND whose existence prevents `unused_file`).
  final Set<String> entryPointPaths;

  /// All annotation simple names that mark a declaration as keep-alive.
  final Set<String> keepAliveAnnotations;

  /// Union of production and test root names. Used as the BFS seed
  /// for the standard `unused_element` rule (anything reachable from
  /// any entry point is considered alive).
  Set<String> get allRootNames => {...productionRootNames, ...testRootNames};
}

/// Resolves entry points from configuration, file paths, generated-code
/// scanning, and annotation presets.
class EntryPointResolver {
  EntryPointResolver({required this.config, required this.presetRegistry});

  final KarekiConfig config;
  final PresetRegistry presetRegistry;

  EntryPointSet resolve({
    required Iterable<ParsedFile> files,
    required Iterable<String> generatedFilePaths,
    required String rootPath,
    required Map<String, String> packageRoots,
    Iterable<String> additionalKeepAlivePaths = const [],
  }) {
    final keepAlivePaths = {...additionalKeepAlivePaths};
    final keepAliveAnnotations = <String>{
      ...presetRegistry.keepAliveAnnotations,
      ...config.customKeepAliveAnnotations,
    };

    // Names explicitly configured as entry-point roots are considered
    // production (a user opt-in for "this symbol is consumed by something
    // external that kareki can't see").
    final productionRootNames = <String>{...config.entryPointNames};
    final testRootNames = <String>{};
    final entryPointPaths = <String>{};

    final extraGlobs = config.entryPointFiles
        .map((g) => Glob(g, recursive: true, caseSensitive: false))
        .toList();

    for (final file in files) {
      // The glob package doesn't match absolute paths (anything starting
      // with `/`), so always reduce to a workspace-relative form before
      // matching.
      final relPath = p.relative(file.path, from: rootPath);
      final isEntry =
          _isImplicitEntryPath(file.path) ||
          // Any file in test/ that defines `main` is executable by
          // `flutter test`, even if its name doesn't end in `_test.dart`
          // (e.g. hand-rolled fixtures under `dartx/test/`).
          (file.hasTopLevelMain && _isInTestDir(file.path)) ||
          extraGlobs.any(
            (g) => g.matches(relPath) || g.matches(p.basename(file.path)),
          );
      if (isEntry) {
        entryPointPaths.add(file.path);
        // Symbols declared in test entry points (test helpers / test
        // bodies themselves) belong to the test bucket; symbols
        // declared in production entry points (main.dart, story files,
        // bin/ scripts) belong to production.
        final pkgRoot = packageRoots[file.packageName] ?? rootPath;
        final bucket = isTestSourcePath(file.path, packageRoot: pkgRoot)
            ? testRootNames
            : productionRootNames;
        for (final declaration in file.declarations) {
          bucket.add(declaration.name);
        }
        // `main` is the conventional Dart entry function and any name a
        // top-level `main*` file already exposes is implicitly reachable.
        bucket.addAll(file.topLevelIdentifierReferences);
      }
    }

    // Generated / excluded code references — every identifier
    // referenced inside such a file seeds the reachability root set,
    // because that code typically references user-written symbols that
    // would otherwise look unused. "Generated" here is the union of:
    //   - files matching `exclude.files` config (user-controlled),
    //   - files whose content begins with a recognizable codegen
    //     marker (detected by `ParsedFile.isGeneratedByHeader`).
    // Both are pre-collected in `additionalKeepAlivePaths` by the
    // runner, so no extension list needs to live here.
    // Generated code is treated as production: codegen output exists
    // to support production behavior (freezed equality, json
    // serializers, route tables, etc.).
    for (final file in files) {
      if (keepAlivePaths.contains(file.path)) {
        productionRootNames.addAll(file.topLevelIdentifierReferences);
      }
    }
    for (final path in generatedFilePaths) {
      // Generated files themselves should not be reported as unused.
      entryPointPaths.add(path);
    }

    // Keep-alive annotations contribute declarations as production
    // roots — annotations such as `@RoutePage` / `@Riverpod` signal
    // framework consumption (production runtime).
    for (final file in files) {
      for (final declaration in file.declarations) {
        if (declaration.annotations.any(keepAliveAnnotations.contains)) {
          productionRootNames.add(declaration.name);
        }
      }
    }

    return EntryPointSet(
      productionRootNames: productionRootNames,
      testRootNames: testRootNames,
      entryPointPaths: entryPointPaths,
      keepAliveAnnotations: keepAliveAnnotations,
    );
  }

  /// Whether [kind] is a public-API kind kareki should report.
  static bool isReportableKind(DeclarationKind kind) {
    switch (kind) {
      case DeclarationKind.classDecl:
      case DeclarationKind.mixinDecl:
      case DeclarationKind.enumDecl:
      case DeclarationKind.extensionDecl:
      case DeclarationKind.typedefDecl:
      case DeclarationKind.function:
      case DeclarationKind.method:
      case DeclarationKind.getter:
      case DeclarationKind.setter:
      case DeclarationKind.field:
      case DeclarationKind.topLevelVariable:
      case DeclarationKind.constructor:
        return true;
    }
  }
}
