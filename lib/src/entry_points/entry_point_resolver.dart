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

/// Result of resolving entry points across a workspace.
class EntryPointSet {
  EntryPointSet({
    required this.rootNames,
    required this.entryPointPaths,
    required this.keepAliveAnnotations,
  });

  /// Simple names that seed the reachability BFS.
  final Set<String> rootNames;

  /// Files considered entry points (whose declarations are all reachable
  /// AND whose existence prevents `unused_file`).
  final Set<String> entryPointPaths;

  /// All annotation simple names that mark a declaration as keep-alive.
  final Set<String> keepAliveAnnotations;
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
    Iterable<String> additionalKeepAlivePaths = const [],
  }) {
    final keepAlivePaths = {...additionalKeepAlivePaths};
    final keepAliveAnnotations = <String>{
      ...presetRegistry.keepAliveAnnotations,
      ...config.customKeepAliveAnnotations,
    };

    final rootNames = <String>{...config.entryPointNames};
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
        for (final declaration in file.declarations) {
          rootNames.add(declaration.name);
        }
        // `main` is the conventional Dart entry function and any name a
        // top-level `main*` file already exposes is implicitly reachable.
        rootNames.addAll(file.topLevelIdentifierReferences);
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
    for (final file in files) {
      if (keepAlivePaths.contains(file.path)) {
        rootNames.addAll(file.topLevelIdentifierReferences);
      }
    }
    for (final path in generatedFilePaths) {
      // Generated files themselves should not be reported as unused.
      entryPointPaths.add(path);
    }

    // Keep-alive annotations contribute declarations as roots.
    for (final file in files) {
      for (final declaration in file.declarations) {
        if (declaration.annotations.any(keepAliveAnnotations.contains)) {
          rootNames.add(declaration.name);
        }
      }
    }

    return EntryPointSet(
      rootNames: rootNames,
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
