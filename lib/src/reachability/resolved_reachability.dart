import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/config/kareki_config.dart';
import 'package:kareki/src/entry_points/entry_point_resolver.dart';
import 'package:kareki/src/model/declaration.dart';
import 'package:kareki/src/parser/declaration_collector.dart';
import 'package:kareki/src/preset/preset_registry.dart';
import 'package:kareki/src/reachability/external_decoder_models.dart';
import 'package:kareki/src/reachability/json_value_origins.dart';
import 'package:path/path.dart' as p;

/// No findings or baselines should be published after incomplete resolution.
class ResolvedAnalysisException implements Exception {
  ResolvedAnalysisException(this.diagnostics);

  final List<String> diagnostics;

  @override
  String toString() =>
      'Resolved analysis incomplete:\n${diagnostics.join('\n')}';
}

/// Analyzer objects never leave the async adapter; existing finding IDs survive.
class ResolvedReachability {
  ResolvedReachability._(
    this.reachable,
    this.productionReachable,
    this.warnings,
    this.argumentUsage,
    this.uncertainCallables,
    this.optionalArgumentStates,
  );

  final Set<DeclarationRecord> reachable;
  final Set<DeclarationRecord> productionReachable;
  final List<String> warnings;
  final Map<DeclarationRecord, CallSiteUsage> argumentUsage;
  final Set<DeclarationRecord> uncertainCallables;
  final Map<OptionalParameterRecord, OptionalArgumentState>
  optionalArgumentStates;

  static Future<ResolvedReachability> build({
    required List<ParsedFile> files,
    required Set<String> generatedPaths,
    required EntryPointSet entryPoints,
    required KarekiConfig config,
    required Map<String, String> packageRoots,
    bool trackArguments = false,
  }) async {
    if (files.isEmpty) return ResolvedReachability._({}, {}, [], {}, {}, {});
    final presets = PresetRegistry(
      enabledPresetNames: config.enabledPresetNames,
      customPresets: config.customPresets,
    );
    final graph = _ResolvedGraph(
      files,
      generatedPaths,
      packageRoots,
      trackArguments: trackArguments,
      keepDriftColumns: presets.keepDriftColumns,
      keepFreezedFactories: presets.keepFreezedFactories,
    );
    final problems = <String>[];
    for (final root in packageRoots.values.toSet()) {
      var directory = p.absolute(root);
      while (!File(
        p.join(directory, '.dart_tool', 'package_config.json'),
      ).existsSync()) {
        final parent = p.dirname(directory);
        if (parent == directory) {
          problems.add(
            '$root: package_config.json is missing; run pub get / workspace bootstrap.',
          );
          break;
        }
        directory = parent;
      }
    }
    if (problems.isNotEmpty) throw ResolvedAnalysisException(problems);
    AnalysisContextCollection? collection;
    var resolving = 'analysis contexts';
    try {
      collection = AnalysisContextCollection(
        includedPaths: packageRoots.values
            .map(graph.canonical)
            .toSet()
            .toList(),
      );
      final visitedUnits = <String>{};
      for (final entry in graph.files.entries) {
        if (visitedUnits.contains(entry.key)) continue;
        resolving = entry.value.path;
        final context = _contextForSource(collection, entry.key);
        final units = <ResolvedUnitResult>[];
        if (File(entry.key).existsSync()) {
          final result = entry.value.partOf == null
              ? await context.currentSession.getResolvedLibrary(entry.key)
              : await context.currentSession.getResolvedLibraryContaining(
                  entry.key,
                );
          if (result is ResolvedLibraryResult &&
              result.units.any(
                (unit) => graph.canonical(unit.path) == entry.key,
              )) {
            units.addAll(result.units);
          } else {
            // An orphan part can still have a resolved unit even when it is
            // absent from its named library. Preserve analyzer's unit-level
            // diagnostics and semantics instead of rejecting it prematurely.
            final unit = await context.currentSession.getResolvedUnit(
              entry.key,
            );
            if (unit is ResolvedUnitResult) units.add(unit);
          }
        }
        // Resolving one part already resolves its entire library. Consume the
        // sibling units now, without retaining ASTs or requesting them again.
        // A part owned by another context must still use its own options and
        // package configuration; dependencies do not become workspace sources.
        for (final unit in units) {
          final path = graph.canonical(unit.path);
          final file = graph.files[path];
          if (!unit.exists ||
              file == null ||
              visitedUnits.contains(path) ||
              !identical(_contextForSource(collection, path), context)) {
            continue;
          }
          visitedUnits.add(path);
          for (final diagnostic in unit.diagnostics) {
            if (diagnostic.diagnosticCode.severity.name != 'ERROR') continue;
            final line = unit.lineInfo
                .getLocation(diagnostic.offset)
                .lineNumber;
            problems.add('${file.path}:$line: ${diagnostic.message}');
          }
          unit.unit.accept(_ResolvedVisitor(graph, path, file));
          graph.collectConditionalFacade(path, unit.unit);
        }
      }
      // Missing units and unavailable libraries share one fail-closed check.
      // A successful sibling must never hide an unresolved collected source.
      for (final entry in graph.files.entries) {
        if (!visitedUnits.contains(entry.key)) {
          problems.add('${entry.value.path}: no resolved compilation unit.');
        }
      }
      if (problems.isNotEmpty) throw ResolvedAnalysisException(problems);
      await graph.summarizeExternalCallbacks();
      graph.finish(entryPoints, config);
      final all = graph.compute(productionOnly: false);
      final production = graph.compute(productionOnly: true);
      return ResolvedReachability._(
        {
          for (final entry in graph.recordIds.entries)
            if (all.contains(entry.value)) entry.key,
        },
        {
          for (final entry in graph.recordIds.entries)
            if (production.contains(entry.value)) entry.key,
        },
        graph.warnings.toList()..sort(),
        {
          for (final entry in graph.recordIds.entries)
            entry.key: ?graph.argumentUsage[entry.value],
        },
        {
          for (final entry in graph.recordIds.entries)
            if (graph.uncertainCallables.contains(entry.value)) entry.key,
        },
        {
          for (final entry in graph.recordIds.entries)
            for (final parameter in entry.key.optionalParameters)
              parameter: graph.argumentState(entry.value, parameter),
        },
      );
    } on ResolvedAnalysisException {
      rethrow;
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        ResolvedAnalysisException(['Cannot resolve $resolving: $error']),
        stack,
      );
    } finally {
      await collection?.dispose();
    }
  }

  static AnalysisContext _contextForSource(
    AnalysisContextCollection collection,
    String path,
  ) {
    // Preserve analyzer's selection for ordinary files. Its contextFor rejects
    // excluded files, even though the owning session can resolve them explicitly.
    if (collection.contexts.any(
      (context) => context.contextRoot.isAnalyzed(path),
    )) {
      return collection.contextFor(path);
    }
    bool contains(String root) => root == path || p.isWithin(root, path);
    final candidates =
        collection.contexts
            .where(
              (context) =>
                  contains(context.contextRoot.root.path) &&
                  context.contextRoot.includedPaths.any(contains),
            )
            .toList()
          ..sort(
            (a, b) => b.contextRoot.root.path.length.compareTo(
              a.contextRoot.root.path.length,
            ),
          );
    if (candidates.isEmpty) {
      throw StateError('No owning analysis context for $path');
    }
    // A nested package config/options root owns its excluded sources, not the
    // ancestor context. Never resolve through an unrelated package's session.
    return candidates.first;
  }
}

// Execution-local only: never persist offsets or analyzer IDs in baselines.
typedef _Id = ({
  String library,
  String unit,
  int offset,
  String kind,
  String? name,
});

class _ResolvedGraph {
  _ResolvedGraph(
    List<ParsedFile> sourceFiles,
    Set<String> generatedPaths,
    this.packageRoots, {
    required this.trackArguments,
    required this.keepDriftColumns,
    required this.keepFreezedFactories,
  }) {
    files.addEntries(sourceFiles.map((f) => MapEntry(canonical(f.path), f)));
    generated.addAll(generatedPaths.map(canonical));
    for (final entry in files.entries) {
      if (!generated.contains(entry.key) &&
          isTestSourcePath(
            entry.value.path,
            packageRoot: packageRoots[entry.value.packageName]!,
          )) {
        _testPaths.add(entry.key);
      }
    }
  }

  final Map<String, String> packageRoots;
  final bool trackArguments;
  final bool keepDriftColumns;
  final bool keepFreezedFactories;
  late final decoderModels = ExternalDecoderModels(
    isWorkspaceSource: (path) => files.containsKey(canonical(path)),
  );
  final argumentUsage = <_Id, CallSiteUsage>{};
  final uncertainCallables = <_Id>{};
  final argumentTargets = <_Id, Set<_Id>>{};
  // Do not retain ASTs: their parent links would pin whole resolved units.
  final callbackSummaries = <_Id, ({bool closed, CallSiteUsage usage})>{};
  final callbackArguments =
      <({_Id target, _Id consumerParameter, String evidence})>[];
  final storedCallbackUsage = <_Id, CallSiteUsage>{};
  final storedCallbackEvidence = <_Id, Set<String>>{};
  final argumentEvidence = <_Id, Set<String>>{};
  final files = <String, ParsedFile>{};
  final generated = <String>{};
  final _testPaths = <String>{};
  final _canonicalPaths = <String, String>{};
  final edges = <_Id, Set<_Id>>{};
  final elements = <_Id, Element>{};
  final _elementIds = Map<Element, _Id>.identity();
  final recordIds = <DeclarationRecord, _Id>{};
  final productionRoots = <_Id>{};
  final testRoots = <_Id>{};
  final warnings = <String>{};
  final unknown = <(_Id, String)>{};
  final unknownSites = <(_Id, String), Set<String>>{};
  final uncertaintyReasons = <_Id, Set<String>>{};
  final conditionalPaths = <String>{};
  final conditionalSites = <String>{};
  final conditionalGroups = <({List<String?> targets, Set<String> sites})>[];
  final conditionalFacades =
      <String, Map<String, ({_Id id, Object type, String kind})>>{};
  final expandedTypes = <_Id>{};

  String canonical(String path) => _canonicalPaths.putIfAbsent(path, () {
    final absolute = p.normalize(p.absolute(path));
    final type = FileSystemEntity.typeSync(absolute);
    if (type == FileSystemEntityType.directory) {
      return Directory(absolute).resolveSymbolicLinksSync();
    }
    if (type == FileSystemEntityType.file) {
      return File(absolute).resolveSymbolicLinksSync();
    }
    return absolute;
  });

  _Id fileId(String path) =>
      (library: path, unit: path, offset: -1, kind: 'UNIT', name: null);

  _Id? ensure(Element? input) {
    if (input == null || input is PrefixElement) return null;
    var element = input.baseElement;
    if (element is PropertyAccessorElement) {
      element = element.nonSynthetic.baseElement;
      if (element is FieldFormalParameterElement && element.field != null) {
        // A primary field's induced accessor points back to its declaring
        // formal, whereas ordinary accessors point back to their field.
        element = element.field!.baseElement;
      }
    }
    if (_elementIds[element] case final cached?) return cached;
    final fragment = element.firstFragment;
    final source = fragment.libraryFragment?.source;
    final library = element.library;
    if (source == null || library == null) return null;
    final id = (
      library: canonical(library.firstFragment.source.fullName),
      unit: canonical(source.fullName),
      // A deferred library's synthetic loadLibrary has no source offset.
      // Keep a library-scoped identity without conflating it with a real
      // same-named function or rooting every declaration in that library.
      offset: element is TopLevelFunctionElement && element.isOriginLoadLibrary
          ? -2
          : fragment.offset,
      kind: element.kind.name,
      name: element.lookupName,
    );
    _elementIds[element] = id;
    if (elements.containsKey(id)) return id;
    elements[id] = element;
    edges.putIfAbsent(id, () => {});
    final host = element.enclosingElement;
    if (host is InstanceElement) edge(id, ensure(host));
    if (element is ConstructorElement) {
      edge(id, ensure(element.superConstructor));
      edge(id, ensure(element.redirectedConstructor));
      if (ensure(element.redirectedConstructor) case final target?) {
        argumentTargets.putIfAbsent(id, () => {}).add(target);
      }
    }
    return id;
  }

  void edge(_Id from, _Id? to) {
    if (to != null) edges.putIfAbsent(from, () => {}).add(to);
  }

  void expandType(InterfaceElement type) {
    final id = ensure(type)!;
    if (!expandedTypes.add(id)) return;
    if (keepDriftColumns) connectDriftColumns(type, id);
    if (keepFreezedFactories) connectFreezedFactories(type, id);
    // Preserve implicit runtime hooks and actual inherited contracts. This is
    // deliberately conservative within a type hierarchy, never across homonyms.
    for (final name in ['call', 'toJson']) {
      edge(id, ensure(type.lookUpMethod(name: name, library: type.library)));
    }
    for (final supertype in type.allSupertypes) {
      final ancestor = supertype.element;
      edge(id, ensure(ancestor));
      for (final member in ancestor.methods.where((m) => !m.isStatic)) {
        final implementation = ensure(
          type.lookUpMethod(name: member.name!, library: ancestor.library),
        );
        final contract = ensure(member)!;
        if (implementation != null) {
          argumentTargets.putIfAbsent(contract, () => {}).add(implementation);
          argumentTargets.putIfAbsent(implementation, () => {}).add(contract);
        }
        edge(id, implementation);
      }
      for (final member in ancestor.getters.where((m) => !m.isStatic)) {
        edge(
          id,
          ensure(
            type.lookUpGetter(name: member.name!, library: ancestor.library),
          ),
        );
      }
      for (final member in ancestor.setters.where((m) => !m.isStatic)) {
        edge(
          id,
          ensure(
            type.lookUpSetter(name: member.name!, library: ancestor.library),
          ),
        );
      }
    }
  }

  // drift_dev reads schema declarations, rather than invoking the original
  // getters at runtime. Generated implementations can override every column.
  // Model this as an edge from the table, not as unconditional keep-alive:
  // unused tables and unrelated same-named types must remain reportable.
  void connectDriftColumns(InterfaceElement type, _Id id) {
    bool isDriftType(InterfaceElement element, String name) =>
        element.name == name &&
        element.library.uri.scheme == 'package' &&
        element.library.uri.pathSegments.first == 'drift';

    final hierarchy = [type, ...type.allSupertypes.map((t) => t.element)];
    if (!hierarchy.any((t) => isDriftType(t, 'Table'))) return;
    for (final owner in hierarchy) {
      for (final field in owner.fields) {
        if (field.isStatic || field.getter == null) continue;
        final column = field.type;
        if (column is! InterfaceType) continue;
        final columnTypes = [column, ...column.allSupertypes];
        if (!columnTypes.any(
          (t) =>
              isDriftType(t.element, 'Column') ||
              (field.isLate &&
                  field.isFinal &&
                  isDriftType(t.element, 'ColumnBuilder')),
        )) {
          continue;
        }
        edge(
          id,
          ensure(type.lookUpGetter(name: field.name!, library: owner.library)),
        );
      }
    }
  }

  // Freezed generates concrete classes from redirecting factory declarations.
  // Direct uses of the generated class need not call the original factory.
  // Resolve the annotation's actual type so homonyms cannot activate this rule.
  void connectFreezedFactories(InterfaceElement type, _Id id) {
    final isFreezed = type.metadata.annotations.any((annotation) {
      final annotationType = annotation.computeConstantValue()?.type;
      if (annotationType is! InterfaceType) return false;
      final declaration = annotationType.element;
      return declaration.name == 'Freezed' &&
          declaration.library.uri.scheme == 'package' &&
          declaration.library.uri.pathSegments.first == 'freezed_annotation';
    });
    if (!isFreezed) return;
    for (final constructor in type.constructors) {
      if (constructor.isFactory && constructor.redirectedConstructor != null) {
        edge(id, ensure(constructor));
      }
    }
  }

  String? conditionalTarget(String from, String uri) {
    final parsed = Uri.tryParse(uri);
    String? target;
    if (parsed?.scheme == 'package' && parsed!.pathSegments.length >= 2) {
      final root = packageRoots[parsed.pathSegments.first];
      if (root != null) {
        target = p.join(root, 'lib', p.joinAll(parsed.pathSegments.skip(1)));
      }
    } else if (parsed != null && !parsed.hasScheme) {
      target = p.normalize(p.join(p.dirname(from), uri));
    }
    return target == null ? null : canonical(target);
  }

  void conditionalDirective(
    String from,
    NamespaceDirective node,
    String Function(AstNode) evidence,
  ) {
    if (node.configurations.isEmpty) return;
    final targets = <String?>[];
    final sites = <String>{};
    void add(StringLiteral literal, String description) {
      final uri = literal.stringValue;
      final target = uri == null ? null : conditionalTarget(from, uri);
      targets.add(target);
      sites.add('$description -> ${uri ?? '<unknown URI>'}');
      if (target != null) conditionalPaths.add(target);
    }

    add(node.uri, '${evidence(node)} default');
    for (final alternative in node.configurations) {
      add(
        alternative.uri,
        '${evidence(alternative)} ${alternative.name.toSource()} == ${alternative.value?.stringValue ?? 'true'}',
      );
    }
    conditionalSites.addAll(sites);
    conditionalGroups.add((targets: targets, sites: sites));
  }

  // A deliberately closed namespace: parameterless functions/getters only,
  // explicit identical nominal return types, no exported types, parts, variables
  // or nested conditional imports. All bodies are resolved by the normal pass.
  // This does not select a platform or claim to validate its SDK/runtime.
  void collectConditionalFacade(String path, CompilationUnit unit) {
    // Production traversal deliberately skips test nodes. A selected test
    // alternative must not cut off the edge to a production alternative.
    if (isTest(fileId(path))) return;
    if (unit.directives.any(
      (d) =>
          d is! ImportDirective && d is! LibraryDirective ||
          d is ImportDirective && d.configurations.isNotEmpty,
    )) {
      return;
    }
    final api = <String, ({_Id id, Object type, String kind})>{};
    for (final declaration in unit.declarations) {
      if (declaration is! FunctionDeclaration) return;
      final element = declaration.declaredFragment?.element;
      if (element is! ExecutableElement ||
          element.formalParameters.isNotEmpty ||
          element.typeParameters.isNotEmpty ||
          declaration.returnType == null ||
          declaration.functionExpression.body is EmptyFunctionBody) {
        return;
      }
      // Removing the old per-file uncertainty must not expose optional
      // parameters on private helpers either, even though they are not exported.
      if (declaration.name.lexeme.startsWith('_')) continue;
      final id = ensure(element);
      if (id == null) return;
      final type = element.returnType;
      Object typeKey;
      if (type is VoidType) {
        typeKey = 'void';
      } else if (type is InterfaceType && type.typeArguments.isEmpty) {
        final typeId = ensure(type.element);
        // Workspace types may themselves vary with a conditional namespace.
        if (typeId == null || files.containsKey(typeId.unit)) return;
        typeKey = (typeId, type.nullabilitySuffix);
      } else {
        // dynamic, Never, function/record/type-parameter and generic returns
        // need a stronger substitution proof than this narrow adapter supports.
        return;
      }
      if (api.containsKey(declaration.name.lexeme)) return;
      api[declaration.name.lexeme] = (
        id: id,
        type: typeKey,
        kind: element.kind.name,
      );
    }
    if (api.isNotEmpty) conditionalFacades[path] = api;
  }

  void connectConditionalFacades() {
    final remainingPaths = <String>{};
    final remainingSites = <String>{};
    for (final group in conditionalGroups) {
      final apis = [for (final path in group.targets) conditionalFacades[path]];
      final first = apis.first;
      final compatible =
          first != null &&
          apis.every(
            (api) =>
                api != null &&
                api.length == first.length &&
                first.entries.every((e) {
                  final other = api[e.key];
                  return other != null &&
                      other.type == e.value.type &&
                      other.kind == e.value.kind;
                }),
          );
      if (!compatible) {
        remainingPaths.addAll(group.targets.whereType<String>());
        remainingSites.addAll(group.sites);
        continue;
      }
      // Taking the union of ALL alternatives over-approximates every condition
      // value, including custom values and unreachable combinations. Identical
      // public signatures keep consumer bindings invariant. Connect only exact
      // declaration IDs within this directive, never unrelated homonyms.
      for (final name in first.keys) {
        final ids = {for (final api in apis) api![name]!.id};
        for (final from in ids) {
          for (final to in ids) {
            edge(from, to);
          }
        }
      }
    }
    // A path shared with an unsupported group must retain its old protection.
    conditionalPaths
      ..clear()
      ..addAll(remainingPaths);
    conditionalSites
      ..clear()
      ..addAll(remainingSites);
  }

  // Classification is constant for this build, including generated-file roots.
  // Reachability may inspect many declarations and edges from the same unit.
  bool isTest(_Id id) => _testPaths.contains(id.unit);

  void finish(EntryPointSet entryPoints, KarekiConfig config) {
    connectConditionalFacades();
    final entryPaths = entryPoints.entryPointPaths.map(canonical).toSet();
    final idsByUnit = <String, Set<_Id>>{};
    for (final id in elements.keys) {
      idsByUnit.putIfAbsent(id.unit, () => {}).add(id);
    }
    for (final file in files.entries) {
      if (entryPaths.contains(file.key) ||
          conditionalPaths.contains(file.key)) {
        final roots =
            generated.contains(file.key) ||
                conditionalPaths.contains(file.key) ||
                !isTest(fileId(file.key))
            ? productionRoots
            : testRoots;
        roots.add(fileId(file.key));
        roots.addAll(idsByUnit[file.key] ?? const {});
        if (conditionalPaths.contains(file.key)) {
          for (final id in idsByUnit[file.key] ?? const <_Id>{}) {
            markUncertain(id, 'Conditional target: ${file.key}');
          }
        }
      }
      for (final record in file.value.declarations) {
        var id = recordIds[record];
        if (id == null) {
          // New analyzer AST forms must not turn an unmapped declaration into
          // an unused finding. Preserve it and expose the precision loss.
          id = (
            library: file.key,
            unit: file.key,
            offset: record.offset,
            kind: record.kind.name,
            name: record.name,
          );
          recordIds[record] = id;
          markUncertain(id, 'Declaration could not be mapped to an element.');
          productionRoots.add(id);
          productionRoots.add(fileId(file.key));
          productionRoots.addAll(idsByUnit[file.key] ?? const {});
          warnings.add(
            'Could not map ${record.libraryPath}:${record.line} ${record.name}; retained conservatively.',
          );
        }
        if (config.entryPointNames.contains(record.name) ||
            record.annotations.any(entryPoints.keepAliveAnnotations.contains)) {
          productionRoots.add(id);
        }
      }
    }
    // Keep one warning per file/name, but retain every source location. Owners
    // (including initializer hosts) may share an AST site.
    final unresolvedEvidence = <(String, String), Set<String>>{};
    final recordsByName = <String, Map<DeclarationRecord, _Id>>{};
    for (final entry in recordIds.entries) {
      recordsByName.putIfAbsent(entry.key.name, () => {})[entry.key] =
          entry.value;
    }
    for (final (owner, name) in unknown) {
      final candidates = recordsByName[name]?.entries ?? const [];
      if (candidates.isEmpty) continue;
      for (final candidate in candidates) {
        edge(owner, candidate.value);
        if (trackArguments) {
          for (final site in unknownSites[(owner, name)]!) {
            markUncertain(candidate.value, 'Unresolved "$name": $site');
          }
        }
      }
      unresolvedEvidence
          .putIfAbsent((owner.unit, name), () => {})
          .addAll(unknownSites[(owner, name)]!);
    }
    for (final entry in unresolvedEvidence.entries) {
      final (unit, name) = entry.key;
      final candidates = recordsByName[name]!.keys.map(
        (record) => '${record.libraryPath}:${record.line} ${record.name}',
      );
      warnings.add(
        'Unresolved reference "$name" in $unit; matching declarations retained conservatively when reachable.'
        '\n  Sites: ${sortedEvidence(entry.value)}'
        '\n  Candidate declarations (not proven targets): ${sortedEvidence(candidates)}'
        '\n  Review: trace receiver values to their concrete types before dismissing candidates. This is not an unused-code finding.',
      );
    }
    if (conditionalPaths.isNotEmpty) {
      warnings.add(
        'Conditional import/export targets are retained conservatively across platforms.'
        '\n  Directives: ${sortedEvidence(conditionalSites)}'
        '\n  Workspace targets: ${sortedEvidence(conditionalPaths)}'
        '\n  Review: validate every supported platform; the selected platform alone cannot establish non-use.',
      );
    }
    if (trackArguments) finishArguments();
  }

  void finishArguments() {
    // All workspace bodies have been visited, independently of file order.
    // Missing/external/virtual/escaping consumers retain the original fallback.
    for (final argument in callbackArguments) {
      if (storedCallbackUsage[argument.consumerParameter] case final usage?) {
        argumentUsage
            .putIfAbsent(argument.target, CallSiteUsage.new)
            .mergeFrom(usage);
        argumentEvidence
            .putIfAbsent(argument.target, () => {})
            .addAll(
              storedCallbackEvidence[argument.consumerParameter] ?? const {},
            );
      }
      final summary = callbackSummaries[argument.consumerParameter];
      if (summary != null && summary.closed) {
        argumentUsage
            .putIfAbsent(argument.target, CallSiteUsage.new)
            .mergeFrom(summary.usage);
      } else {
        markUncertain(argument.target, 'Function value: ${argument.evidence}');
      }
    }
    // Propagate only through real override/redirect relationships, never names.
    for (final source in {...argumentUsage.keys, ...uncertainCallables}) {
      final pending = [source];
      final visited = <_Id>{};
      while (pending.isNotEmpty) {
        final target = pending.removeLast();
        if (!visited.add(target)) continue;
        if (argumentUsage[source] case final usage?) {
          argumentUsage.putIfAbsent(target, CallSiteUsage.new).mergeFrom(usage);
        }
        if (argumentEvidence[source] case final evidence?) {
          argumentEvidence.putIfAbsent(target, () => {}).addAll(evidence);
        }
        if (uncertainCallables.contains(source)) {
          uncertainCallables.add(target);
          uncertaintyReasons
              .putIfAbsent(target, () => {})
              .addAll(uncertaintyReasons[source]!);
        }
        pending.addAll(argumentTargets[target] ?? const <_Id>{});
      }
    }
    for (final entry in recordIds.entries) {
      if (!uncertainCallables.contains(entry.value)) continue;
      final unproven = entry.key.optionalParameters
          .where(
            (parameter) =>
                argumentState(entry.value, parameter) ==
                OptionalArgumentState.unknown,
          )
          .map(
            (parameter) => parameter.isNamed
                ? 'named ${parameter.name}'
                : 'positional ${parameter.positionalIndex! + 1} (${parameter.name})',
          )
          .toList();
      if (unproven.isNotEmpty) {
        final usage = argumentUsage[entry.value];
        final evidence = argumentEvidence[entry.value];
        warnings.add(
          'Argument usage for ${entry.key.libraryPath}:${entry.key.line} ${entry.key.name} is uncertain; optional parameters retained conservatively.'
          '\n  Unproven parameters: ${sortedEvidence(unproven)}'
          '\n  Known argument evidence (including forwarding): max positional ${usage?.maxPositionalArgs ?? 0}; named ${sortedEvidence(usage?.namedArgsPassed ?? const <String>{})}'
          '${evidence == null ? '' : '\n  Callback invocation evidence (potential field flow, not runtime execution): ${sortedEvidence(evidence)}'}'
          '\n  Reasons: ${sortedEvidence(uncertaintyReasons[entry.value]!)}'
          '\n  Review: trace these function values to calls, storage, returns and forwarding. Lack of evidence is not proof of non-use.',
        );
      }
    }
  }

  Future<void> summarizeExternalCallbacks() async {
    // Resolve only directly selected consumers, in their original analysis
    // session. Dependencies are not added as finding/entry-point sources.
    final requested = <LibraryElement, Set<_Id>>{};
    final storedRoots = <LibraryElement>{};
    for (final argument in callbackArguments) {
      if (callbackSummaries.containsKey(argument.consumerParameter)) continue;
      final parameter = elements[argument.consumerParameter];
      final library = parameter?.library;
      if (parameter is! FormalParameterElement ||
          library == null ||
          library.isInSdk ||
          files.containsKey(argument.consumerParameter.unit)) {
        continue;
      }
      requested.putIfAbsent(library, () => {}).add(argument.consumerParameter);
      if (parameter.enclosingElement is ConstructorElement) {
        storedRoots.add(library);
      }
    }
    for (final entry in requested.entries) {
      try {
        final result = await entry.key.session.getResolvedLibraryByElement(
          entry.key,
        );
        if (result is! ResolvedLibraryResult ||
            result.units.any(
              (unit) =>
                  !unit.exists ||
                  unit.diagnostics.any(
                    (diagnostic) =>
                        diagnostic.diagnosticCode.severity.name == 'ERROR',
                  ),
            )) {
          continue;
        }
        for (final unit in result.units) {
          unit.unit.accept(_CallbackDeclarations(this, entry.value));
        }
      } on Object {
        // An unavailable external body never establishes non-use. Its original
        // function-value site will still produce the conservative fallback.
        continue;
      }
    }
    await summarizeStoredCallbacks(storedRoots);
  }

  Future<void> summarizeStoredCallbacks(Set<LibraryElement> roots) async {
    final groups = <(Object, String), Set<LibraryElement>>{};
    for (final root in roots) {
      if (root.uri.scheme != 'package') continue;
      final package = root.uri.pathSegments.first;
      groups.putIfAbsent((root.session, package), () => {}).add(root);
    }
    for (final entry in groups.entries) {
      final package = entry.key.$2;
      final libraries = <LibraryElement>{};
      final pending = entry.value.toList();
      var complete = true;
      while (pending.isNotEmpty) {
        final library = pending.removeLast();
        if (library.uri.scheme != 'package' ||
            library.uri.pathSegments.first != package ||
            !libraries.add(library)) {
          continue;
        }
        // Bounded, package-local evidence collection. A large or incomplete
        // dependency never changes an unknown callback into non-use.
        if (libraries.length > 128 ||
            library.fragments.any(
              (fragment) =>
                  files.containsKey(canonical(fragment.source.fullName)),
            )) {
          complete = false;
          break;
        }
        pending.addAll(library.exportedLibraries);
        for (final fragment in library.fragments) {
          pending.addAll(fragment.importedLibraries);
        }
      }
      if (!complete) continue;
      final flow = _StoredCallbackFlow(this);
      try {
        for (final library in libraries) {
          final result = await library.session.getResolvedLibraryByElement(
            library,
          );
          if (result is! ResolvedLibraryResult ||
              result.units.any(
                (unit) =>
                    !unit.exists ||
                    unit.diagnostics.any(
                      (diagnostic) =>
                          diagnostic.diagnosticCode.severity.name == 'ERROR',
                    ),
              )) {
            complete = false;
            break;
          }
          for (final unit in result.units) {
            unit.unit.accept(flow);
          }
        }
        if (complete) flow.apply();
      } on Object {
        // No evidence from an incomplete package scan is committed.
        continue;
      }
    }
  }

  void summarizeCallbacks(
    AstNode node,
    Element element, {
    Set<_Id>? requested,
  }) {
    if (!trackArguments) return;
    final body = switch (node) {
      FunctionDeclaration() when element is TopLevelFunctionElement =>
        node.functionExpression.body,
      MethodDeclaration()
          when element is MethodElement &&
              (element.isStatic ||
                  element.enclosingElement is ExtensionElement) =>
        node.body,
      _ => null,
    };
    // A sync* body may keep its callback in the compiler's private iterator
    // state, but every source-level use must still be a direct invocation.
    // Yielding the callback itself, forwarding, aliases and captures fail below.
    if (body == null ||
        body.isAsynchronous ||
        body is! BlockFunctionBody && body is! ExpressionFunctionBody) {
      return;
    }
    for (final parameter in (element as ExecutableElement).formalParameters) {
      if (parameter.type is! FunctionType) continue;
      final id = ensure(parameter)!;
      if (requested != null && !requested.contains(id)) continue;
      final summary = _ImmediateCallbackSummary(parameter.baseElement, body);
      body.accept(summary);
      callbackSummaries[id] = (closed: summary.closed, usage: summary.usage);
    }
  }

  OptionalArgumentState argumentState(
    _Id id,
    OptionalParameterRecord parameter,
  ) {
    if (!trackArguments) return OptionalArgumentState.unknown;
    final usage = argumentUsage[id];
    final passed = parameter.isNamed
        ? (usage?.namedArgsPassed.contains(parameter.name) ?? false)
        : (usage?.maxPositionalArgs ?? 0) > parameter.positionalIndex!;
    if (passed) return OptionalArgumentState.used;
    return uncertainCallables.contains(id)
        ? OptionalArgumentState.unknown
        : OptionalArgumentState.unused;
  }

  void forwardSuperParameter(FormalParameterElement input) {
    if (!trackArguments) return;
    final parameter = input.baseElement;
    final constructor = parameter.enclosingElement! as ConstructorElement;
    final id = ensure(constructor)!;
    final usage = argumentUsage.putIfAbsent(id, CallSiteUsage.new);
    // A super formal supplies this argument on every invocation, including
    // its default value when the caller omits the child's optional parameter.
    if (parameter.isNamed) {
      usage.mergeNamed(parameter.name!);
    } else {
      usage.mergePositional(
        constructor.formalParameters.indexOf(parameter) + 1,
      );
    }
  }

  static String sortedEvidence(Iterable<String> values) =>
      (values.toSet().toList()..sort()).join(' | ');

  void markUncertain(_Id id, String reason) {
    uncertainCallables.add(id);
    uncertaintyReasons.putIfAbsent(id, () => {}).add(reason);
  }

  void escape(
    Element? element,
    String evidence, {
    FormalParameterElement? consumer,
  }) {
    if (!trackArguments || element is! ExecutableElement) return;
    if (ensure(element) case final id?) {
      final parameter = ensure(consumer);
      if (parameter == null) {
        markUncertain(id, 'Function value: $evidence');
      } else {
        callbackArguments.add((
          target: id,
          consumerParameter: parameter,
          evidence: evidence,
        ));
      }
    }
  }

  Set<_Id> compute({required bool productionOnly}) {
    final visited = <_Id>{};
    final pending = <_Id>[
      ...productionRoots,
      if (!productionOnly) ...testRoots,
    ];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (productionOnly && isTest(id)) continue;
      if (!visited.add(id)) continue;
      pending.addAll(edges[id] ?? const <_Id>{});
    }
    return visited;
  }
}

/// Positive-only, instance-insensitive evidence. This graph can retain arguments
/// as potentially used; it can NEVER close an escaped callback or prove non-use.
/// It recognizes unchanged constructor forwarding, redirects and final fields,
/// not arbitrary assignments, aliases, getters or cross-package flows.
class _StoredCallbackFlow extends RecursiveAstVisitor<void> {
  _StoredCallbackFlow(this.graph);

  final _ResolvedGraph graph;
  final transfers = <_Id, Set<_Id>>{};
  final invalid = <_Id>{};
  final calls = <_Id, CallSiteUsage>{};
  final sites = <_Id, Set<String>>{};

  void transfer(Element source, Element target) {
    final from = graph.ensure(source);
    final to = graph.ensure(target);
    if (from != null && to != null) {
      transfers.putIfAbsent(from, () => {}).add(to);
    }
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final constructor = node.declaredFragment?.element;
    if (constructor != null) {
      final redirect = constructor.redirectedConstructor;
      var position = 0;
      for (final parameter in constructor.formalParameters) {
        if (parameter.type is FunctionType) {
          if (parameter is FieldFormalParameterElement) {
            final field = parameter.field;
            if (field != null && field.isFinal && field.type is FunctionType) {
              transfer(parameter, field);
            }
          }
          // Only a redirecting factory implicitly forwards all its formals.
          // Generative this(...) arguments are checked as explicit expressions.
          if (constructor.isFactory && redirect != null) {
            final candidates = redirect.formalParameters
                .where(
                  (target) => parameter.isNamed
                      ? target.isNamed && target.name == parameter.name
                      : target.isPositional,
                )
                .toList();
            final index = parameter.isNamed ? 0 : position;
            if (index < candidates.length &&
                candidates[index].type is FunctionType) {
              transfer(parameter, candidates[index]);
            }
          }
        }
        if (parameter.isPositional) position++;
      }
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    final id = graph.ensure(node.element);
    if (id != null) invalid.add(id);
    super.visitAssignedVariablePattern(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parameter = node.element?.baseElement;
    if (!node.inDeclarationContext() &&
        node.parent is! Label &&
        parameter is FormalParameterElement &&
        parameter.type is FunctionType &&
        parameter.enclosingElement is ConstructorElement) {
      final context = _ResolvedVisitor.argumentContext(node);
      final call = context?.list.parent;
      final callee = switch (call) {
        InstanceCreationExpression() => call.constructorName.element,
        SuperConstructorInvocation() => call.element,
        RedirectingConstructorInvocation() => call.element,
        _ => null,
      };
      FormalParameterElement? target;
      // Reassignment, casts, captures and other unmodeled uses invalidate the
      // parameter's transfers, independent of statement/initialization order.
      if (context != null &&
          callee != null &&
          node.thisOrAncestorOfType<FunctionExpression>() == null) {
        var position = 0;
        for (final argument in context.list.arguments) {
          final name = argument.beginToken.next?.lexeme == ':'
              ? argument.beginToken.lexeme
              : null;
          if (argument == context.value || argument == context.parent) {
            final matches = callee.baseElement.formalParameters
                .where(
                  (formal) => name == null
                      ? formal.isPositional
                      : formal.isNamed && formal.name == name,
                )
                .toList();
            final index = name == null ? position : 0;
            if (index < matches.length && matches[index].type is FunctionType) {
              target = matches[index];
            }
            break;
          }
          if (name == null) position++;
        }
      }
      if (target == null) {
        invalid.add(graph.ensure(parameter)!);
      } else {
        transfer(parameter, target);
      }
    }
    super.visitSimpleIdentifier(node);
  }

  FieldElement? fieldOf(Expression? input) {
    var expression = input;
    while (expression is ParenthesizedExpression ||
        expression is PostfixExpression && expression.operator.lexeme == '!') {
      expression = expression is ParenthesizedExpression
          ? expression.expression
          : (expression! as PostfixExpression).operand;
    }
    final element = switch (expression) {
      SimpleIdentifier() => expression.element,
      PrefixedIdentifier() => expression.identifier.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };
    final value = element is PropertyAccessorElement
        ? element.nonSynthetic.baseElement
        : element?.baseElement;
    return value is FieldElement && value.isFinal && value.type is FunctionType
        ? value
        : null;
  }

  void record(FieldElement? field, ArgumentList arguments) {
    if (field == null) return;
    final id = graph.ensure(field)!;
    final usage = calls.putIfAbsent(id, CallSiteUsage.new);
    var positional = 0;
    for (final argument in arguments.arguments) {
      if (argument.beginToken.next?.lexeme == ':') {
        usage.mergeNamed(argument.beginToken.lexeme);
      } else {
        positional++;
      }
    }
    usage.mergePositional(positional);
    final unit = arguments.root as CompilationUnit;
    final location = unit.lineInfo.getLocation(arguments.offset);
    final source = unit.declaredFragment?.source.fullName;
    sites
        .putIfAbsent(id, () => {})
        .add(
          '${field.enclosingElement.name}.${field.name}: $source:${location.lineNumber}:${location.columnNumber}',
        );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'call' &&
        node.methodName.element == null &&
        node.realTarget?.staticType is FunctionType) {
      record(fieldOf(node.realTarget), node.argumentList);
    } else {
      record(fieldOf(node.methodName), node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    record(fieldOf(node.function), node.argumentList);
    super.visitFunctionExpressionInvocation(node);
  }

  void apply() {
    for (final root
        in graph.callbackArguments
            .map((argument) => argument.consumerParameter)
            .toSet()) {
      final visited = <_Id>{};
      final pending = [root];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (!visited.add(current) || invalid.contains(current)) continue;
        if (calls[current] case final usage?) {
          graph.storedCallbackUsage
              .putIfAbsent(root, CallSiteUsage.new)
              .mergeFrom(usage);
          graph.storedCallbackEvidence
              .putIfAbsent(root, () => {})
              .addAll(sites[current]!);
        }
        pending.addAll(transfers[current] ?? const <_Id>{});
      }
    }
  }
}

/// A deliberately small, intraprocedural proof. Every reference to the actual
/// parameter element must be a direct invocation in this synchronous body.
/// Returning a call's result is allowed; returning/storing/casting/reassigning
/// the function itself, capturing it or forwarding it invalidates the proof.
class _ImmediateCallbackSummary extends RecursiveAstVisitor<void> {
  _ImmediateCallbackSummary(this.parameter, this.body);

  final FormalParameterElement parameter;
  final FunctionBody body;
  final usage = CallSiteUsage();
  bool closed = true;

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    // Pattern assignment stores its binding as a token, not a SimpleIdentifier.
    if (node.element?.baseElement == parameter) closed = false;
    super.visitAssignedVariablePattern(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element?.baseElement == parameter) {
      final parent = node.parent;
      final arguments = switch (parent) {
        MethodInvocation()
            when parent.methodName == node && parent.target == null ||
                parent.target == node &&
                    parent.methodName.name == 'call' &&
                    parent.methodName.element == null =>
          parent.argumentList,
        FunctionExpressionInvocation() when parent.function == node =>
          parent.argumentList,
        _ => null,
      };
      if (arguments == null ||
          node.thisOrAncestorOfType<FunctionBody>() != body) {
        closed = false;
      } else {
        var positional = 0;
        for (final argument in arguments.arguments) {
          if (argument.beginToken.next?.lexeme == ':') {
            usage.mergeNamed(argument.beginToken.lexeme);
          } else {
            positional++;
          }
        }
        usage.mergePositional(positional);
      }
    }
    super.visitSimpleIdentifier(node);
  }
}

/// Read dependency declarations without creating dependency graph edges or
/// retaining resolved ASTs after their compact summaries have been computed.
class _CallbackDeclarations extends GeneralizingAstVisitor<void> {
  _CallbackDeclarations(this.graph, this.requested);

  final _ResolvedGraph graph;
  final Set<_Id> requested;

  @override
  void visitNode(AstNode node) {
    if (node is Declaration) {
      final element = node.declaredFragment?.element;
      if (element != null) {
        graph.summarizeCallbacks(node, element, requested: requested);
      }
    }
    super.visitNode(node);
  }
}

class _ResolvedVisitor extends GeneralizingAstVisitor<void> {
  _ResolvedVisitor(this.graph, this.path, this.file)
    : owner = graph.fileId(path) {
    for (final record in file.declarations) {
      _recordsByName.putIfAbsent(record.name, () => []).add(record);
    }
  }

  final _ResolvedGraph graph;
  final String path;
  final ParsedFile file;
  final _recordsByName = <String, List<DeclarationRecord>>{};
  _Id owner;
  _Id? initializerHost;
  JsonValueOrigins? _jsonOrigins;

  // Accept only the complete argument expression, never a value hidden inside
  // a closure, conditional, cast, collection or other escaping expression.
  static ({AstNode value, AstNode? parent, ArgumentList list})? argumentContext(
    AstNode node,
  ) {
    var value = node;
    while (true) {
      final parent = value.parent;
      if (parent is PrefixedIdentifier && parent.identifier == value ||
          parent is PropertyAccess && parent.propertyName == value ||
          parent is ConstructorReference && parent.constructorName == value ||
          parent is ParenthesizedExpression && parent.expression == value) {
        value = parent!;
      } else {
        break;
      }
    }
    final parent = value.parent;
    final list = parent is ArgumentList
        ? parent
        : parent?.parent is ArgumentList &&
              parent?.beginToken.next?.lexeme == ':'
        ? parent!.parent! as ArgumentList
        : null;
    if (list == null) return null;
    return (value: value, parent: parent, list: list);
  }

  FormalParameterElement? consumerParameter(AstNode node) {
    final context = argumentContext(node);
    if (context == null) return null;
    final (:value, :parent, :list) = context;
    final call = list.parent;
    final callee = switch (call) {
      MethodInvocation() => call.methodName.element?.baseElement,
      InstanceCreationExpression() => call.constructorName.element?.baseElement,
      SuperConstructorInvocation() => call.element?.baseElement,
      RedirectingConstructorInvocation() => call.element?.baseElement,
      _ => null,
    };
    // A function variable's inferred type may retain the original function's
    // parameter elements even after reassignment. Its signature is not proof
    // that this invocation executes that original consumer body.
    if (callee is! TopLevelFunctionElement &&
        callee is! ConstructorElement &&
        !(callee is MethodElement &&
            (callee.isStatic || callee.enclosingElement is ExtensionElement))) {
      return null;
    }
    var position = 0;
    final parameters = (callee! as ExecutableElement).formalParameters;
    for (final argument in list.arguments) {
      final name = argument.beginToken.next?.lexeme == ':'
          ? argument.beginToken.lexeme
          : null;
      if (argument == value || argument == parent) {
        // Generic instantiation may produce signature parameters with no
        // enclosing declaration. Map the argument to the *verified callee's*
        // original formal by name/position instead of trusting that signature.
        return name == null
            ? parameters.where((p) => p.isPositional).elementAt(position)
            : parameters.firstWhere((p) => p.isNamed && p.name == name);
      }
      if (name == null) position++;
    }
    return null;
  }

  String callbackEvidence(AstNode node) {
    final site = evidence(node);
    final call = argumentContext(node)?.list.parent;
    if (call is! MethodInvocation) return site;
    final callee = call.methodName.element?.baseElement;
    if (callee is! MethodElement ||
        callee.isStatic ||
        callee.enclosingElement is ExtensionElement ||
        callee.enclosingElement is ExtensionTypeElement ||
        call.realTarget is SuperExpression) {
      return site;
    }
    // These are static bindings, not a points-to proof. In particular, a final
    // field/getter or a cast does not establish the receiver's concrete class.
    // Keep this diagnostic path separate from callback/argument summaries.
    final receiver = call.realTarget;
    final references = <String>[];
    var current = receiver;
    while (current != null) {
      final element = switch (current) {
        SimpleIdentifier() => current.element,
        PrefixedIdentifier() => current.identifier.element,
        PropertyAccess() => current.propertyName.element,
        _ => null,
      };
      if (element != null) references.add(declarationEvidence(element));
      current = switch (current) {
        PrefixedIdentifier() => current.prefix,
        PropertyAccess() => current.realTarget,
        ParenthesizedExpression() => current.expression,
        _ => null,
      };
    }
    return '$site; consumer dispatch: virtual; static consumer: ${declarationEvidence(callee)}'
        '; consumer receiver type: ${receiver?.staticType?.getDisplayString() ?? 'implicit/unavailable'}'
        '${references.isEmpty ? '' : '; receiver references (static only, leaf to root): ${references.join(' <- ')}'}'
        '; boundary: concrete receiver and callback forwarding are unproven';
  }

  String declarationEvidence(Element input) {
    var element = input.baseElement;
    if (element is PropertyAccessorElement) {
      element = element.nonSynthetic.baseElement;
    }
    final fragment = element.firstFragment;
    final source = fragment.libraryFragment?.source;
    final host = element.enclosingElement;
    final label = host is InstanceElement
        ? '${host.name}.${element.name}'
        : element.name ?? element.kind.name;
    if (source == null) return label;
    final sourcePath = graph.canonical(source.fullName);
    // Reuse the resolved source snapshot rather than rereading the file, which
    // could have changed or become unavailable after resolution.
    final location = fragment.libraryFragment!.lineInfo.getLocation(
      fragment.offset,
    );
    return '$label at $sourcePath:${location.lineNumber}:${location.columnNumber}';
  }

  String evidence(AstNode node) {
    final unit = node.root as CompilationUnit;
    final location = unit.lineInfo.getLocation(node.offset);
    final end = unit.lineInfo.getLocation(node.end);
    final receiver = switch (node) {
      SimpleIdentifier(parent: final PrefixedIdentifier parent) =>
        parent.prefix,
      SimpleIdentifier(parent: final PropertyAccess parent) =>
        parent.realTarget,
      SimpleIdentifier(parent: final MethodInvocation parent) =>
        parent.realTarget,
      IndexExpression() => node.realTarget,
      _ => null,
    };
    // Locations, AST kinds and static types are sufficient to locate/review the
    // evidence without copying potentially sensitive source literals into logs.
    return '$path:${location.lineNumber}:${location.columnNumber}'
        ' (end: ${end.lineNumber}:${end.columnNumber}; ${node.runtimeType}; context: ${node.parent.runtimeType}'
        '${receiver == null ? '' : '; receiver type: ${receiver.staticType?.getDisplayString() ?? 'unavailable'}'}'
        ')';
  }

  @override
  void visitNode(AstNode node) {
    final previous = owner;
    final previousInitializer = initializerHost;
    final element = switch (node) {
      Declaration() => node.declaredFragment?.element,
      PrimaryConstructorDeclaration() => node.declaredFragment?.element,
      _ => null,
    };
    if (element != null) {
      graph.summarizeCallbacks(node, element);
      final id = graph.ensure(element)!;
      owner = id;
      initializerHost = null;
      final name = element is ConstructorElement && element.name == 'new'
          ? element.enclosingElement.name
          : element.name;
      for (final record
          in _recordsByName[name] ?? const <DeclarationRecord>[]) {
        if (record.offset >= node.offset &&
            record.offset < node.end &&
            _matches(record, element)) {
          graph.recordIds[record] = id;
        }
      }
      if (element is InterfaceElement) graph.expandType(element);
      // Primary constructor fields have no VariableDeclaration; their field
      // fragment offset can be the class name. The declaring parameter provides
      // both the precise source position and the actual associated field.
      if (element is ConstructorElement) {
        for (final parameter in element.formalParameters) {
          if (parameter is! FieldFormalParameterElement ||
              parameter.field == null) {
            continue;
          }
          for (final record
              in _recordsByName[parameter.name] ??
                  const <DeclarationRecord>[]) {
            if (record.kind == DeclarationKind.field &&
                record.offset == parameter.firstFragment.offset) {
              graph.recordIds[record] = graph.ensure(parameter.field)!;
            }
          }
        }
      }
      if (element is LocalVariableElement) graph.edge(previous, id);
      if (element is FieldElement &&
          node is VariableDeclaration &&
          node.initializer != null) {
        initializerHost = graph.ensure(element.enclosingElement);
      }
    }
    if (node is FieldFormalParameter) {
      final parameter = node.declaredFragment?.element;
      if (parameter is FieldFormalParameterElement) {
        reference(parameter.field, parameter.name ?? '', node);
      }
    }
    if (node is EnumConstantDeclaration) {
      reference(node.constructorElement, node.name.lexeme, node);
    }
    if (node is SuperFormalParameter) {
      final parameter = node.declaredFragment?.element;
      if (parameter is SuperFormalParameterElement) {
        if (parameter.superConstructorParameter case final target?) {
          graph.forwardSuperParameter(target);
        }
      }
    }
    super.visitNode(node);
    owner = previous;
    initializerHost = previousInitializer;
  }

  bool _matches(DeclarationRecord record, Element element) {
    final name = element is ConstructorElement && element.name == 'new'
        ? element.enclosingElement.name
        : element.name;
    if (record.name != name) return false;
    return switch (record.kind) {
      DeclarationKind.classDecl => element is ClassElement,
      DeclarationKind.mixinDecl => element is MixinElement,
      DeclarationKind.enumDecl => element is EnumElement,
      DeclarationKind.extensionDecl =>
        element is ExtensionElement || element is ExtensionTypeElement,
      DeclarationKind.typedefDecl => element is TypeAliasElement,
      DeclarationKind.function => element is TopLevelFunctionElement,
      DeclarationKind.method => element is MethodElement,
      DeclarationKind.getter => element is GetterElement,
      DeclarationKind.setter => element is SetterElement,
      DeclarationKind.field => element is FieldElement,
      DeclarationKind.topLevelVariable => element is TopLevelVariableElement,
      DeclarationKind.constructor => element is ConstructorElement,
    };
  }

  void reference(Element? element, String spelling, AstNode node) {
    // Newer analyzer versions expose a DynamicElement with no library, both
    // in type annotations and type literals. It is never an unknown target.
    if (element is PrefixElement || element?.kind == ElementKind.DYNAMIC) {
      return;
    }
    final id = graph.ensure(element);
    if (id == null) {
      graph.unknown.add((owner, spelling));
      final site = evidence(node);
      graph.unknownSites.putIfAbsent((owner, spelling), () => {}).add(site);
      if (initializerHost case final host?) {
        graph.unknown.add((host, spelling));
        graph.unknownSites.putIfAbsent((host, spelling), () => {}).add(site);
      }
    } else {
      graph.edge(owner, id);
      if (initializerHost case final host?) graph.edge(host, id);
    }
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext() &&
        node.parent is! Label &&
        !_isStructuralMember(node)) {
      final parent = node.parent;
      final directCall =
          parent is MethodInvocation && parent.methodName == node ||
          parent is DotShorthandInvocation && parent.memberName == node ||
          parent is DotShorthandConstructorInvocation ||
          parent is ConstructorName ||
          parent is SuperConstructorInvocation ||
          parent is RedirectingConstructorInvocation ||
          parent is Annotation;
      // Import/export combinators select names; they do not pass function
      // values to unknown callers. Keep their existing reference edges.
      if (graph.trackArguments &&
          node.element is ExecutableElement &&
          !directCall &&
          parent is! Combinator) {
        graph.escape(
          node.element,
          callbackEvidence(node),
          consumer: consumerParameter(node),
        );
      }
      final assignment = _assignmentFor(node);
      if (assignment == null) {
        reference(node.element, node.name, node);
      } else {
        final elements = {assignment.readElement, assignment.writeElement}
          ..remove(null);
        if (elements.isEmpty) reference(null, node.name, node);
        for (final element in elements) {
          reference(element, node.name, node);
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  // Record fields and a function type's built-in call have no declaration
  // Element. Do not turn structural accesses into same-name fallback edges.
  // Real members (including extensions and callable classes) still resolve
  // normally. Visiting the receiver and arguments also remains unchanged.
  bool _isStructuralMember(SimpleIdentifier node) {
    if (node.element != null) return false;
    final parent = node.parent;
    final receiver = switch (parent) {
      PrefixedIdentifier() when parent.identifier == node => parent.prefix,
      PropertyAccess() when parent.propertyName == node => parent.realTarget,
      MethodInvocation() when parent.methodName == node => parent.realTarget,
      _ => null,
    };
    final type = receiver?.staticType;
    if (type is RecordType) {
      return type.namedFields.any((field) => field.name == node.name) ||
          List.generate(
            type.positionalFields.length,
            (index) => '\$${index + 1}',
          ).contains(node.name);
    }
    return type is FunctionType && node.name == 'call';
  }

  CompoundAssignmentExpression? _assignmentFor(AstNode identifier) {
    var node = identifier;
    while (true) {
      final parent = node.parent;
      if (parent is PrefixedIdentifier && parent.identifier == node ||
          parent is PropertyAccess && parent.propertyName == node) {
        node = parent!;
      } else if (parent is AssignmentExpression &&
          parent.leftHandSide == node) {
        return parent;
      } else if (parent is PostfixExpression &&
          parent.operand == node &&
          {'++', '--'}.contains(parent.operator.lexeme)) {
        return parent;
      } else if (parent is PrefixExpression &&
          parent.operand == node &&
          {'++', '--'}.contains(parent.operator.lexeme)) {
        return parent;
      } else {
        return null;
      }
    }
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.element != null ||
        !{'void', 'dynamic'}.contains(node.name.lexeme)) {
      reference(node.element, node.name.lexeme, node);
    }
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    reference(node.element, node.name?.name ?? node.type.name.lexeme, node);
    if (node.parent is ConstructorReference) {
      graph.escape(
        node.element,
        callbackEvidence(node),
        consumer: consumerParameter(node),
      );
    }
    super.visitConstructorName(node);
  }

  @override
  void visitImplicitCallReference(ImplicitCallReference node) {
    reference(node.element, 'call', node);
    graph.escape(
      node.element,
      callbackEvidence(node),
      consumer: consumerParameter(node),
    );
    super.visitImplicitCallReference(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    if (graph.trackArguments) {
      final parent = node.parent;
      final target = switch (parent) {
        MethodInvocation() => parent.methodName.element,
        InstanceCreationExpression() => parent.constructorName.element,
        DotShorthandConstructorInvocation() => parent.element,
        DotShorthandInvocation() => parent.memberName.element,
        FunctionExpressionInvocation() => parent.element,
        SuperConstructorInvocation() => parent.element,
        RedirectingConstructorInvocation() => parent.element,
        Annotation() => parent.element,
        EnumConstantArguments() =>
          (parent.parent! as EnumConstantDeclaration).constructorElement,
        _ => null,
      };
      if (target is ExecutableElement) {
        final id = graph.ensure(target)!;
        final usage = graph.argumentUsage.putIfAbsent(id, CallSiteUsage.new);
        var positional = 0;
        for (final argument in node.arguments) {
          final name = argument.beginToken;
          if (name.next?.lexeme == ':') {
            usage.mergeNamed(name.lexeme);
          } else {
            positional++;
          }
        }
        usage.mergePositional(positional);
      }
    }
    super.visitArgumentList(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    reference(node.element, node.constructorName?.name ?? 'new', node);
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    reference(node.element, node.constructorName?.name ?? 'new', node);
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    reference(node.element, node.operator.lexeme, node);
    super.visitBinaryExpression(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    final assignment = _assignmentFor(node);
    if (assignment == null) {
      final decodedValue =
          node.element == null &&
          (_jsonOrigins ??= JsonValueOrigins(
            node.root as CompilationUnit,
            graph.decoderModels,
          )).isDecodedIndex(node);
      if (!decodedValue) reference(node.element, '[]', node);
    } else {
      if (assignment.readElement != null) {
        reference(assignment.readElement, '[]', node);
      }
      reference(assignment.writeElement, '[]=', node);
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.element != null) {
      reference(node.element, node.operator.lexeme, node);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.element != null) {
      reference(node.element, node.operator.lexeme, node);
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.element != null) {
      reference(node.element, node.operator.lexeme, node);
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitPatternField(PatternField node) {
    if (node.element != null) {
      reference(node.element, node.effectiveName ?? '', node);
    }
    super.visitPatternField(node);
  }

  @override
  void visitImportDirective(ImportDirective node) {
    graph.conditionalDirective(path, node, evidence);
    super.visitImportDirective(node);
  }

  @override
  void visitExportDirective(ExportDirective node) {
    graph.conditionalDirective(path, node, evidence);
    super.visitExportDirective(node);
  }

  @override
  void visitCommentReference(CommentReference node) {}
}
