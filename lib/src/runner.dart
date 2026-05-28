import 'dart:io';

import 'package:glob/glob.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/dependency/pub_dependency_checker.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/model/finding.dart';
import 'package:kareki/src/model/package_info.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:kareki/src/preset/preset_registry.dart';
import 'package:kareki/src/reachability/reachability_graph.dart';
import 'package:kareki/src/reachability/unused_file_detector.dart';
import 'package:kareki/src/workspace/workspace_loader.dart';
import 'package:path/path.dart' as p;

/// Configurable input for [KarekiRunner.run].
class RunRequest {
  /// Creates a run request. [rootPath] is the absolute path of the
  /// workspace root (the directory holding `kareki-config.yaml`,
  /// `melos.yaml`, and/or root `pubspec.yaml`).
  RunRequest({
    required this.rootPath,
    required this.config,
    this.includePackages,
    this.enabledRules,
    this.strictDependencies = false,
    this.disregardFileLevelIgnores = false,
  });

  /// Workspace root used for package discovery, glob matching, and
  /// relative-path reporting.
  final String rootPath;

  /// Parsed `kareki-config.yaml`, or [KarekiConfig.defaults] for
  /// out-of-the-box behaviour.
  final KarekiConfig config;

  /// Optional override; restrict analysis to these package names.
  /// `null` means "all packages in the workspace".
  final Set<String>? includePackages;

  /// Optional override; only run these rules. `null` means "all rules
  /// not excluded by `KarekiConfig.ignoreRules`".
  final Set<String>? enabledRules;

  /// When `true`, `unused_pub_dependency` also flags entries under
  /// `dev_dependencies:` (default: `false`).
  final bool strictDependencies;

  /// When `true`, `// kareki: ignore_for_file=...` directives are
  /// **not** applied — findings normally suppressed by the directive
  /// are emitted as if it were absent. Used by `kareki doctor` to
  /// figure out which directives actually suppress something and which
  /// are dead.
  final bool disregardFileLevelIgnores;
}

/// Result of one analysis run.
class RunResult {
  /// Creates a run result. Produced by [KarekiRunner.run]; user code
  /// usually only consumes instances.
  RunResult({
    required this.findings,
    required this.packagesAnalyzed,
    required this.filesAnalyzed,
    required this.elapsed,
  });

  /// All detections produced by the run, in deterministic order
  /// suitable for direct rendering or baseline diffs.
  final List<Finding> findings;

  /// Number of workspace packages that were analyzed (after applying
  /// `ignore.packages` and `--packages` filters).
  final int packagesAnalyzed;

  /// Number of non-generated `.dart` files contributing to the
  /// reachability index.
  final int filesAnalyzed;

  /// Wall-clock duration of the run.
  final Duration elapsed;
}

/// Orchestrates workspace discovery, parsing, entry-point resolution,
/// reachability BFS, and rule evaluation.
///
/// Stateless — instantiate once and call [run] for each analysis.
class KarekiRunner {
  /// Executes a single analysis described by [request] and returns the
  /// collected findings.
  RunResult run(RunRequest request) {
    final stopwatch = Stopwatch()..start();

    final workspaceLoader = WorkspaceLoader(rootPath: request.rootPath);
    final allPackages = workspaceLoader.load(
      include: request.config.includePackages,
      exclude: request.config.excludePackages,
    );

    final packages = allPackages.where((pkg) {
      if (request.config.ignorePackages.contains(pkg.name)) return false;
      if (request.includePackages != null &&
          !request.includePackages!.contains(pkg.name)) {
        return false;
      }
      return true;
    }).toList();

    final excludeGlobs = request.config.excludeFiles
        .map((pattern) => Glob(pattern, recursive: true))
        .toList();

    final collector = DeclarationCollector();
    final parsedFiles = <ParsedFile>[];
    final generatedPaths = <String>{};

    for (final pkg in packages) {
      for (final file in _dartFilesIn(pkg)) {
        final relForGlob = p.relative(file.path, from: request.rootPath);
        final excluded = excludeGlobs.any(
          (g) => g.matches(relForGlob) || g.matches(p.basename(file.path)),
        );
        ParsedFile? parsed;
        try {
          parsed = collector.collect(
            path: file.path,
            packageName: pkg.name,
            content: file.readAsStringSync(),
          );
        } on Object {
          // Skip files the parser cannot read.
          continue;
        }
        parsedFiles.add(parsed);
        if (excluded || parsed.isGeneratedByHeader) {
          generatedPaths.add(file.path);
        }
      }
    }

    final presetRegistry = PresetRegistry(
      enabledPresetNames: request.config.enabledPresetNames,
      customPresets: request.config.customPresets,
    );

    final entryResolver = EntryPointResolver(
      config: request.config,
      presetRegistry: presetRegistry,
    );
    final packageRoots = <String, String>{
      for (final pkg in packages) pkg.name: pkg.rootPath,
    };
    final entryPoints = entryResolver.resolve(
      files: parsedFiles,
      // Treat every excluded file as "generated" for keep-alive purposes:
      // its internal identifier references seed the reachability root set,
      // so symbols only used by excluded code (e.g. base classes inherited
      // by *.fake.dart) are not falsely reported as unused.
      generatedFilePaths: generatedPaths,
      additionalKeepAlivePaths: generatedPaths,
      rootPath: request.rootPath,
      packageRoots: packageRoots,
    );

    final declarationFiles = parsedFiles
        .where((f) => !generatedPaths.contains(f.path))
        .toList();
    final index = DeclarationIndex.fromRecords(
      declarationFiles.expand((f) => f.declarations),
    );
    final bfs = ReachabilityBfs();
    // BFS from all entry points (production ∪ test). Used by
    // `unused_element` — anything reachable from any entry point is
    // alive.
    final reachable = bfs.compute(
      index: index,
      roots: entryPoints.allRootNames,
    );
    // BFS from production entry points only. A declaration reachable
    // from `reachable` but not from `productionReachable` is consumed
    // only by tests (`test_only_used`).
    //
    // Filter out declarations in test source so that production roots
    // sharing a simple name with a test declaration (e.g. `main`
    // declared in both `bin/main.dart` and `test/foo_test.dart`)
    // don't transitively pull in test-only symbols via the test
    // declaration's outgoing edges.
    bool isRecordInTestSource(DeclarationRecord record) {
      final pkgRoot = packageRoots[record.packageName];
      if (pkgRoot == null) return false;
      return isTestSourcePath(record.libraryPath, packageRoot: pkgRoot);
    }

    final productionReachable = bfs.compute(
      index: index,
      roots: entryPoints.productionRootNames,
      filter: (record) => !isRecordInTestSource(record),
    );

    final fileIgnores = <String, Set<String>>{
      for (final file in declarationFiles) file.path: file.fileLevelIgnores,
    };
    final lineIgnores = <String, Map<int, Set<String>>>{
      for (final file in declarationFiles) file.path: file.lineLevelIgnores,
    };

    // Returns `true` when the finding at (path, line) is silenced by a
    // `// kareki: ignore=<rule|name>` directive matching either the
    // rule id or the declaration/parameter simple name. Disabled along
    // with file-level directives under `disregardFileLevelIgnores` so
    // `kareki doctor` can detect stale per-line directives the same way
    // it does for `ignore_for_file`.
    bool isLineIgnored(String path, int line, String ruleId, String? name) {
      if (request.disregardFileLevelIgnores) return false;
      final byLine = lineIgnores[path];
      if (byLine == null) return false;
      final set = byLine[line];
      if (set == null) return false;
      if (set.contains(ruleId)) return true;
      if (name != null && set.contains(name)) return true;
      return false;
    }

    final findings = <Finding>[];

    final unusedElementEnabled = _ruleEnabled(RuleId.unusedElement, request);
    final testOnlyUsedEnabled = _ruleEnabled(RuleId.testOnlyUsed, request);

    if (unusedElementEnabled || testOnlyUsedEnabled) {
      for (final declaration in index.all) {
        if (!declaration.isPublic) continue;
        // Operator methods (`<`, `[]`, `+`, ...) are called via syntactic
        // sugar (`a < b`, `obj[i]`), not via a SimpleIdentifier. The
        // simple-name BFS can never reach them, so reporting is always a
        // false positive.
        if (_isOperatorName(declaration.name)) continue;
        // A "public" member of a library-private type (`_Foo.bar`) is only
        // reachable from inside the library and is already covered by
        // `dart analyze`'s built-in unused_element. Skip to avoid duplicate
        // reports.
        final enclosingTypeName = declaration.enclosingTypeName;
        if (enclosingTypeName != null && enclosingTypeName.startsWith('_')) {
          continue;
        }
        if (request.config.excludeNames.contains(declaration.name)) continue;
        if (declaration.annotations.any(
          entryPoints.keepAliveAnnotations.contains,
        )) {
          continue;
        }

        final ignores = request.disregardFileLevelIgnores
            ? const <String>{}
            : (fileIgnores[declaration.libraryPath] ?? const {});
        final isReachable =
            reachable.contains(declaration) ||
            entryPoints.allRootNames.contains(declaration.name);
        final isProductionReachable =
            productionReachable.contains(declaration) ||
            entryPoints.productionRootNames.contains(declaration.name);

        // `@override` declarations are framework / supertype contract
        // implementations: invoked via dynamic dispatch whenever the
        // enclosing type is reachable (e.g. `CustomPainter.shouldRepaint`,
        // `Widget.build`). Reporting them as unused is almost always a
        // false positive caused by the simple-name BFS not modeling
        // virtual dispatch.
        var hasReachableOverrideHost = false;
        var hasProductionReachableOverrideHost = false;
        if (declaration.annotations.contains('override') &&
            enclosingTypeName != null) {
          final enclosing = index.enclosingType(declaration);
          if (enclosing != null) {
            if (reachable.contains(enclosing)) {
              hasReachableOverrideHost = true;
            }
            if (productionReachable.contains(enclosing)) {
              hasProductionReachableOverrideHost = true;
            }
          }
        }

        if (unusedElementEnabled && !isReachable && !hasReachableOverrideHost) {
          if (!ignores.contains(RuleId.unusedElement) &&
              !ignores.contains(declaration.name) &&
              !isLineIgnored(
                declaration.libraryPath,
                declaration.line,
                RuleId.unusedElement,
                declaration.name,
              )) {
            findings.add(
              Finding(
                ruleId: RuleId.unusedElement,
                severity: Severity.warning,
                message: _messageFor(declaration),
                packageName: declaration.packageName,
                filePath: declaration.libraryPath,
                line: declaration.line,
                column: declaration.column,
                length: declaration.length,
                stableId: declaration.stableId,
              ),
            );
          }
          continue;
        }

        // test_only_used: declaration is reachable, but not from
        // production. Only meaningful when the declaration itself
        // lives in production source — flagging test helpers
        // (declared in `test/`) just because they're not used in
        // production would be noise. `@override` members of
        // production-reachable types are excluded for the same
        // reason as for `unused_element`: virtual dispatch from
        // production code never appears as a SimpleIdentifier and
        // would otherwise yield false positives.
        if (testOnlyUsedEnabled &&
            isReachable &&
            !isProductionReachable &&
            !hasProductionReachableOverrideHost &&
            !isRecordInTestSource(declaration)) {
          if (ignores.contains(RuleId.testOnlyUsed) ||
              ignores.contains(declaration.name)) {
            continue;
          }
          if (isLineIgnored(
            declaration.libraryPath,
            declaration.line,
            RuleId.testOnlyUsed,
            declaration.name,
          )) {
            continue;
          }
          findings.add(
            Finding(
              ruleId: RuleId.testOnlyUsed,
              severity: Severity.warning,
              message: _testOnlyMessageFor(declaration),
              packageName: declaration.packageName,
              filePath: declaration.libraryPath,
              line: declaration.line,
              column: declaration.column,
              length: declaration.length,
              stableId: declaration.stableId,
            ),
          );
        }
      }
    }

    if (_ruleEnabled(RuleId.unusedParameter, request)) {
      for (final file in declarationFiles) {
        final ignores = request.disregardFileLevelIgnores
            ? const <String>{}
            : file.fileLevelIgnores;
        if (ignores.contains(RuleId.unusedParameter)) continue;
        for (final declaration in file.declarations) {
          if (declaration.unusedParameters.isEmpty) continue;
          // A declaration kept alive by a codegen annotation has a
          // signature dictated by the framework — flagging its params
          // would be noise.
          if (declaration.annotations.any(
            entryPoints.keepAliveAnnotations.contains,
          )) {
            continue;
          }
          for (final param in declaration.unusedParameters) {
            if (ignores.contains(param.name)) continue;
            if (isLineIgnored(
              declaration.libraryPath,
              param.line,
              RuleId.unusedParameter,
              param.name,
            )) {
              continue;
            }
            findings.add(
              Finding(
                ruleId: RuleId.unusedParameter,
                severity: Severity.warning,
                message: _unusedParameterMessageFor(declaration, param),
                packageName: declaration.packageName,
                filePath: declaration.libraryPath,
                line: param.line,
                column: param.column,
                length: param.length,
                stableId: '${declaration.stableId}|param:${param.name}',
              ),
            );
          }
        }
      }
    }

    if (_ruleEnabled(RuleId.unusedParameterOptional, request)) {
      // Aggregate call-site usage across every parsed file in the
      // workspace — including generated and excluded files. A
      // generated client passing `endpoint:` to a hand-written
      // constructor is a legitimate consumer of that parameter.
      final aggregated = <String, CallSiteUsage>{};
      for (final file in parsedFiles) {
        file.callSiteUsage.forEach((name, usage) {
          aggregated.putIfAbsent(name, CallSiteUsage.new).mergeFrom(usage);
        });
      }

      for (final file in declarationFiles) {
        final ignores = request.disregardFileLevelIgnores
            ? const <String>{}
            : file.fileLevelIgnores;
        if (ignores.contains(RuleId.unusedParameterOptional)) continue;
        for (final declaration in file.declarations) {
          if (declaration.optionalParameters.isEmpty) continue;
          if (declaration.annotations.any(
            entryPoints.keepAliveAnnotations.contains,
          )) {
            continue;
          }
          // Skip "public" members of library-private types — they can
          // only be reached from inside the library and are already
          // covered (and more precisely so) by Dart analyzer's own
          // hints.
          final enclosing = declaration.enclosingTypeName;
          if (enclosing != null && enclosing.startsWith('_')) continue;

          final usage = aggregated[declaration.name];
          for (final param in declaration.optionalParameters) {
            if (ignores.contains(param.name)) continue;
            final passed = _optionalParameterPassed(param, usage);
            if (passed) continue;
            if (isLineIgnored(
              declaration.libraryPath,
              param.line,
              RuleId.unusedParameterOptional,
              param.name,
            )) {
              continue;
            }
            findings.add(
              Finding(
                ruleId: RuleId.unusedParameterOptional,
                severity: Severity.warning,
                message: _unusedOptionalParameterMessageFor(declaration, param),
                packageName: declaration.packageName,
                filePath: declaration.libraryPath,
                line: param.line,
                column: param.column,
                length: param.length,
                stableId: '${declaration.stableId}|optparam:${param.name}',
              ),
            );
          }
        }
      }
    }

    if (_ruleEnabled(RuleId.unusedFile, request)) {
      // Pass all parsed files (including generated) so that imports from
      // generated code count as references. Generated files themselves are
      // present in entryPointPaths and therefore never reported.
      findings.addAll(
        UnusedFileDetector().detect(
          packages: packages,
          files: parsedFiles,
          entryPointPaths: entryPoints.entryPointPaths,
        ),
      );
    }

    if (_ruleEnabled(RuleId.unusedPubDependency, request)) {
      final filesByPackage = <String, List<ParsedFile>>{};
      for (final file in parsedFiles) {
        filesByPackage.putIfAbsent(file.packageName, () => []).add(file);
      }
      // Merge preset-derived mappings with top-level
      // `annotation_implied_packages` from config so both contribute.
      final annotationImpliedPackages = {
        ...presetRegistry.annotationImpliedPackages,
      };
      request.config.annotationImpliedPackages.forEach((annotation, packages) {
        annotationImpliedPackages
            .putIfAbsent(annotation, () => <String>{})
            .addAll(packages);
      });

      for (final pkg in packages) {
        findings.addAll(
          PubDependencyChecker().check(
            package: pkg,
            filesInPackage: filesByPackage[pkg.name] ?? const [],
            ignoredDeps:
                request.config.ignoredDependencies[pkg.name] ?? const {},
            annotationImpliedPackages: annotationImpliedPackages,
            sdkPackages: request.config.sdkPackages,
            strict: request.strictDependencies,
          ),
        );
      }
    }

    stopwatch.stop();
    return RunResult(
      findings: findings,
      packagesAnalyzed: packages.length,
      filesAnalyzed: declarationFiles.length,
      elapsed: stopwatch.elapsed,
    );
  }

  bool _ruleEnabled(String rule, RunRequest request) {
    if (request.config.ignoreRules.contains(rule)) return false;
    if (request.enabledRules == null) return true;
    return request.enabledRules!.contains(rule);
  }

  bool _isOperatorName(String name) {
    if (name.isEmpty) return false;
    final first = name.codeUnitAt(0);
    // Identifiers start with a letter or underscore. Operators start with
    // any other character: `<`, `>`, `=`, `[`, `+`, `-`, `*`, `/`, `~`,
    // `&`, `|`, `^`, `%`, `!`.
    final isLetter =
        (first >= 0x41 && first <= 0x5A) ||
        (first >= 0x61 && first <= 0x7A) ||
        first == 0x5F;
    return !isLetter;
  }

  String _messageFor(DeclarationRecord declaration) {
    final qualifier = declaration.enclosingTypeName != null
        ? '${declaration.enclosingTypeName}.${declaration.name}'
        : declaration.name;
    return "Unused public ${declaration.kind.name} '$qualifier'.";
  }

  String _unusedParameterMessageFor(
    DeclarationRecord declaration,
    ParameterRecord parameter,
  ) {
    final qualifier = declaration.enclosingTypeName != null
        ? '${declaration.enclosingTypeName}.${declaration.name}'
        : declaration.name;
    return "Parameter '${parameter.name}' of '$qualifier' is never used.";
  }

  String _unusedOptionalParameterMessageFor(
    DeclarationRecord declaration,
    OptionalParameterRecord parameter,
  ) {
    final enclosing = declaration.enclosingTypeName;
    // Unnamed constructors are recorded under the class's simple name
    // (so `Foo(...)` call sites can be matched), which would otherwise
    // render the qualifier as `Foo.Foo` — collapse it to just `Foo()`.
    final qualifier = enclosing == null
        ? declaration.name
        : enclosing == declaration.name &&
              declaration.kind == DeclarationKind.constructor
        ? '$enclosing()'
        : '$enclosing.${declaration.name}';
    return "Optional parameter '${parameter.name}' of '$qualifier' is "
        'never passed at any call site.';
  }

  bool _optionalParameterPassed(
    OptionalParameterRecord parameter,
    CallSiteUsage? usage,
  ) {
    if (usage == null) return false;
    if (parameter.isNamed) {
      return usage.namedArgsPassed.contains(parameter.name);
    }
    final index = parameter.positionalIndex;
    if (index == null) return false;
    return usage.maxPositionalArgs > index;
  }

  String _testOnlyMessageFor(DeclarationRecord declaration) {
    final qualifier = declaration.enclosingTypeName != null
        ? '${declaration.enclosingTypeName}.${declaration.name}'
        : declaration.name;
    return "Public ${declaration.kind.name} '$qualifier' is only "
        'referenced from test code.';
  }

  Iterable<File> _dartFilesIn(PackageInfo pkg) sync* {
    for (final sub in ['lib', 'bin', 'test', 'integration_test', 'example']) {
      final dir = Directory(p.join(pkg.rootPath, sub));
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith('.dart')) continue;
        // Skip pub workspace build / tool outputs.
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
