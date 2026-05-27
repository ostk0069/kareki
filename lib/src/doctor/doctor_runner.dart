import 'dart:io';

import 'package:glob/glob.dart';
import 'package:kareki/src/baseline/baseline.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/doctor/doctor_finding.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:kareki/src/runner.dart';
import 'package:kareki/src/workspace/workspace_loader.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Names of `kareki-config.yaml` (and historical aliases) that doctor
/// reads to recover the *user-supplied* values, before they get merged
/// with defaults by [KarekiConfig.load].
const _configCandidates = <String>[
  'kareki-config.yaml',
  'kareki_config.yaml',
  'kareki.yaml',
];

class _UserConfig {
  _UserConfig({
    required this.excludeFiles,
    required this.ignorePackages,
    required this.ignoredDependencies,
  });

  /// User-specified entries in `exclude.files`. Empty when the user
  /// did not override it — in which case doctor must not flag the
  /// defaults baked into [KarekiConfig.defaults].
  final List<String> excludeFiles;
  final Set<String> ignorePackages;
  final Map<String, Set<String>> ignoredDependencies;

  /// Loads the raw user values from the config file. Returns an empty
  /// config when no file exists, which causes doctor to find nothing
  /// (there is nothing for the user to clean up).
  factory _UserConfig.load(String rootPath) {
    File? file;
    for (final name in _configCandidates) {
      final candidate = File(p.join(rootPath, name));
      if (candidate.existsSync()) {
        file = candidate;
        break;
      }
    }
    if (file == null) return _UserConfig.empty;
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap) return _UserConfig.empty;
    final exclude = yaml['exclude'] as YamlMap?;
    final ignore = yaml['ignore'] as YamlMap?;
    return _UserConfig(
      excludeFiles: _stringList(exclude?['files']),
      ignorePackages: _stringSet(ignore?['packages']),
      ignoredDependencies: _stringSetMap(ignore?['dependencies']),
    );
  }

  static final empty = _UserConfig(
    excludeFiles: const [],
    ignorePackages: const {},
    ignoredDependencies: const {},
  );

  static List<String> _stringList(Object? node) {
    if (node is YamlList) return node.map((e) => e.toString()).toList();
    return const [];
  }

  static Set<String> _stringSet(Object? node) {
    if (node is YamlList) return node.map((e) => e.toString()).toSet();
    return const {};
  }

  static Map<String, Set<String>> _stringSetMap(Object? node) {
    if (node is! YamlMap) return const {};
    return {
      for (final entry in node.entries)
        entry.key.toString(): _stringSet(entry.value),
    };
  }
}

/// Configurable input for [DoctorRunner.run].
class DoctorRequest {
  DoctorRequest({required this.rootPath, required this.config});

  /// Workspace root, same semantics as [RunRequest.rootPath].
  final String rootPath;

  /// Parsed `kareki-config.yaml`.
  final KarekiConfig config;
}

/// Result of one `doctor` invocation.
class DoctorResult {
  DoctorResult({required this.findings, required this.elapsed});

  /// Issues found in the configuration, in deterministic order.
  final List<DoctorFinding> findings;

  /// Wall-clock duration of the run.
  final Duration elapsed;
}

/// Validates `kareki-config.yaml` against the actual state of the
/// workspace, surfacing stale `exclude` globs, ignore entries that no
/// longer match any real package/dependency, and `// kareki:
/// ignore_for_file=...` directives that suppress nothing.
class DoctorRunner {
  /// Executes one health check pass.
  DoctorResult run(DoctorRequest request) {
    final stopwatch = Stopwatch()..start();
    final findings = <DoctorFinding>[];

    final user = _UserConfig.load(request.rootPath);
    final allPackages = WorkspaceLoader(rootPath: request.rootPath).load(
      include: request.config.includePackages,
      exclude: request.config.excludePackages,
    );
    final analyzedPackages = allPackages
        .where((pkg) => !request.config.ignorePackages.contains(pkg.name))
        .toList();
    final workspacePackageNames = allPackages.map((p) => p.name).toSet();

    findings.addAll(_findDeadExcludeGlobs(request, user, analyzedPackages));
    findings.addAll(_findDeadIgnorePackages(user, workspacePackageNames));
    findings.addAll(_findDeadIgnoreDependencies(user, allPackages));
    findings.addAll(_findUnusedIgnoreDirectives(request, analyzedPackages));
    findings.addAll(_findStaleBaselineEntries(request));

    findings.sort((a, b) {
      final byKind = a.kind.compareTo(b.kind);
      if (byKind != 0) return byKind;
      final bySubject = a.subject.compareTo(b.subject);
      if (bySubject != 0) return bySubject;
      return (a.detail ?? '').compareTo(b.detail ?? '');
    });

    stopwatch.stop();
    return DoctorResult(findings: findings, elapsed: stopwatch.elapsed);
  }

  Iterable<DoctorFinding> _findDeadExcludeGlobs(
    DoctorRequest request,
    _UserConfig user,
    List<PackageInfo> analyzedPackages,
  ) sync* {
    if (user.excludeFiles.isEmpty) return;
    final globs = {
      for (final pattern in user.excludeFiles)
        pattern: Glob(pattern, recursive: true),
    };
    final hits = <String, int>{for (final pattern in globs.keys) pattern: 0};
    for (final pkg in analyzedPackages) {
      for (final file in _dartFilesIn(pkg)) {
        final rel = p.relative(file.path, from: request.rootPath);
        final base = p.basename(file.path);
        for (final entry in globs.entries) {
          if (entry.value.matches(rel) || entry.value.matches(base)) {
            hits[entry.key] = hits[entry.key]! + 1;
          }
        }
      }
    }
    for (final entry in hits.entries) {
      if (entry.value == 0) {
        yield DoctorFinding(
          kind: DoctorIssueKind.unusedExclude,
          subject: entry.key,
          detail: 'exclude.files',
        );
      }
    }
  }

  Iterable<DoctorFinding> _findDeadIgnorePackages(
    _UserConfig user,
    Set<String> workspacePackageNames,
  ) sync* {
    for (final name in user.ignorePackages) {
      if (!workspacePackageNames.contains(name)) {
        yield DoctorFinding(
          kind: DoctorIssueKind.unusedIgnorePackage,
          subject: name,
          detail: 'ignore.packages',
        );
      }
    }
  }

  Iterable<DoctorFinding> _findDeadIgnoreDependencies(
    _UserConfig user,
    List<PackageInfo> allPackages,
  ) sync* {
    final byName = {for (final pkg in allPackages) pkg.name: pkg};
    for (final entry in user.ignoredDependencies.entries) {
      final pkg = byName[entry.key];
      if (pkg == null) {
        yield DoctorFinding(
          kind: DoctorIssueKind.unusedIgnoreDependenciesPackage,
          subject: entry.key,
          detail: 'ignore.dependencies',
        );
        continue;
      }
      final declared = <String>{...pkg.dependencies, ...pkg.devDependencies};
      for (final dep in entry.value) {
        if (!declared.contains(dep)) {
          yield DoctorFinding(
            kind: DoctorIssueKind.unusedIgnoreDependency,
            subject: '${entry.key} -> $dep',
            detail: 'ignore.dependencies.${entry.key}',
          );
        }
      }
    }
  }

  Iterable<DoctorFinding> _findUnusedIgnoreDirectives(
    DoctorRequest request,
    List<PackageInfo> analyzedPackages,
  ) sync* {
    final excludeGlobs = request.config.excludeFiles
        .map((pattern) => Glob(pattern, recursive: true))
        .toList();
    final collector = DeclarationCollector();
    // For each file with at least one file-level ignore, remember which
    // names are ignored.
    final fileIgnores = <String, Set<String>>{};
    // For each file with at least one `// kareki: ignore=...` directive,
    // remember which names are ignored on which line.
    final lineIgnoresByPath = <String, Map<int, Set<String>>>{};
    for (final pkg in analyzedPackages) {
      for (final file in _dartFilesIn(pkg)) {
        final rel = p.relative(file.path, from: request.rootPath);
        final base = p.basename(file.path);
        final excluded = excludeGlobs.any(
          (g) => g.matches(rel) || g.matches(base),
        );
        if (excluded) continue;
        String content;
        try {
          content = file.readAsStringSync();
        } on Object {
          continue;
        }
        // Cheap guard: only parse files that mention the directive.
        if (!content.contains('kareki:')) continue;
        try {
          final parsed = collector.collect(
            path: file.path,
            packageName: pkg.name,
            content: content,
          );
          if (parsed.fileLevelIgnores.isNotEmpty) {
            fileIgnores[file.path] = parsed.fileLevelIgnores;
          }
          if (parsed.lineLevelIgnores.isNotEmpty) {
            lineIgnoresByPath[file.path] = parsed.lineLevelIgnores;
          }
        } on Object {
          continue;
        }
      }
    }

    if (fileIgnores.isEmpty && lineIgnoresByPath.isEmpty) return;

    // Run a full analysis with comment-based ignores DISABLED, so the
    // findings list contains every detection — including the ones the
    // directives suppress. A directive that maps to none of those raw
    // findings is genuinely dead.
    final findings = KarekiRunner()
        .run(
          RunRequest(
            rootPath: request.rootPath,
            config: request.config,
            disregardFileLevelIgnores: true,
          ),
        )
        .findings;

    // For each file in fileIgnores, build the set of "names that would
    // have matched a finding from that file" — both rule ids (the
    // directive suppresses a whole rule for the file) and the simple
    // symbol names appearing in finding messages quoted as `'name'`
    // (per-symbol suppression). A name in fileIgnores that does not
    // appear in this matched set is reported as unused.
    final matchedByFile = <String, Set<String>>{};
    // Same idea, but keyed by (file, line) so we can validate per-line
    // directives without false negatives when the same rule fires on
    // another line of the file.
    final matchedByFileLine = <String, Map<int, Set<String>>>{};
    final symbolPattern = RegExp(r"'([\w_]+)'");
    for (final finding in findings) {
      final matched = matchedByFile.putIfAbsent(finding.filePath, () => {})
        ..add(finding.ruleId);
      final byLine = matchedByFileLine.putIfAbsent(finding.filePath, () => {});
      final lineSet = byLine.putIfAbsent(finding.line, () => <String>{})
        ..add(finding.ruleId);
      for (final m in symbolPattern.allMatches(finding.message)) {
        matched.add(m.group(1)!);
        lineSet.add(m.group(1)!);
      }
    }

    for (final entry in fileIgnores.entries) {
      final matched = matchedByFile[entry.key] ?? const <String>{};
      for (final name in entry.value) {
        if (!matched.contains(name)) {
          yield DoctorFinding(
            kind: DoctorIssueKind.unusedIgnoreDirective,
            subject: p.relative(entry.key, from: request.rootPath),
            detail: name,
          );
        }
      }
    }

    for (final entry in lineIgnoresByPath.entries) {
      final byLine = matchedByFileLine[entry.key] ?? const <int, Set<String>>{};
      final relPath = p.relative(entry.key, from: request.rootPath);
      for (final lineEntry in entry.value.entries) {
        final matchedAtLine = byLine[lineEntry.key] ?? const <String>{};
        for (final name in lineEntry.value) {
          if (!matchedAtLine.contains(name)) {
            yield DoctorFinding(
              kind: DoctorIssueKind.unusedIgnoreDirective,
              subject: '$relPath:${lineEntry.key}',
              detail: name,
            );
          }
        }
      }
    }
  }

  Iterable<DoctorFinding> _findStaleBaselineEntries(
    DoctorRequest request,
  ) sync* {
    final baselinePath = request.config.baselinePath;
    if (baselinePath == null || baselinePath.isEmpty) return;
    final absPath = p.isAbsolute(baselinePath)
        ? baselinePath
        : p.normalize(p.join(request.rootPath, baselinePath));
    if (!File(absPath).existsSync()) return;
    final Baseline baseline;
    try {
      final loaded = Baseline.load(absPath);
      if (loaded == null) return;
      baseline = loaded;
    } on FormatException {
      // Malformed baseline is surfaced by the main runner; doctor stays
      // silent to avoid duplicate error spam.
      return;
    }

    final findings = KarekiRunner()
        .run(RunRequest(rootPath: request.rootPath, config: request.config))
        .findings;

    // Compare against the *unfiltered* finding set, because cli.dart
    // already subtracts the baseline before reporting. Re-running here
    // with the baseline applied would hide every real finding and make
    // every baseline entry look stale.
    final stale = baseline.staleKeys(findings, rootPath: request.rootPath);
    if (stale.isEmpty) return;

    // Stable display order: sort by the raw key string.
    final sorted = stale.toList()..sort();
    for (final key in sorted) {
      yield DoctorFinding(
        kind: DoctorIssueKind.unusedBaselineEntry,
        subject: key,
        detail: 'baseline',
      );
    }
  }

  Iterable<File> _dartFilesIn(PackageInfo pkg) sync* {
    for (final sub in ['lib', 'bin', 'test', 'integration_test', 'example']) {
      final dir = Directory(p.join(pkg.rootPath, sub));
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        if (entity.path.contains('${p.separator}.dart_tool${p.separator}')) {
          continue;
        }
        if (entity.path.contains('${p.separator}build${p.separator}')) {
          continue;
        }
        yield entity;
      }
    }
  }
}
