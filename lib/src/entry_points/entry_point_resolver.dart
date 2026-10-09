import 'package:glob/glob.dart';
import 'package:kareki/src/config/kareki_config.dart';
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
    required this.entryPointPaths,
    required this.keepAliveAnnotations,
  });

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
    required Map<String, String> packageRoots,
    Iterable<String> additionalKeepAlivePaths = const [],
  }) {
    final keepAliveAnnotations = <String>{
      ...presetRegistry.keepAliveAnnotations,
      ...config.customKeepAliveAnnotations,
    };

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
          // Any collected top-level main can be invoked with dart run,
          // including root/tool scripts and custom-named test executables.
          file.hasTopLevelMain ||
          extraGlobs.any(
            (g) => g.matches(relPath) || g.matches(p.basename(file.path)),
          );
      if (isEntry) {
        entryPointPaths.add(file.path);
      }
    }

    entryPointPaths.addAll(generatedFilePaths);
    entryPointPaths.addAll(additionalKeepAlivePaths);

    return EntryPointSet(
      entryPointPaths: entryPointPaths,
      keepAliveAnnotations: keepAliveAnnotations,
    );
  }
}
