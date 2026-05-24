/// A kind of declaration that can be detected as unused.
enum DeclarationKind {
  classDecl,
  mixinDecl,
  enumDecl,
  extensionDecl,
  typedefDecl,
  function,
  method,
  getter,
  setter,
  field,
  topLevelVariable,
  constructor,
}

/// A parameter declared by a callable (function / method / constructor)
/// that is not referenced inside the callable's body or initializers.
///
/// Populated by [DeclarationCollector] and consumed by the runner's
/// `unused_parameter` rule.
class ParameterRecord {
  ParameterRecord({
    required this.name,
    required this.line,
    required this.column,
    required this.length,
    required this.offset,
  });

  final String name;
  final int line;
  final int column;
  final int length;
  final int offset;
}

/// An optional parameter declared by a callable, tracked regardless of
/// whether it is referenced in the body. Populated by
/// [DeclarationCollector] and consumed by the runner's
/// `unused_parameter_optional` rule, which flags entries for which no
/// call site in the workspace passes a value.
class OptionalParameterRecord {
  OptionalParameterRecord({
    required this.name,
    required this.line,
    required this.column,
    required this.length,
    required this.offset,
    required this.isNamed,
    this.positionalIndex,
  });

  final String name;
  final int line;
  final int column;
  final int length;
  final int offset;

  /// `true` for named optional parameters (`{...}`). `false` for
  /// positional optional parameters (`[...]`).
  final bool isNamed;

  /// 0-based index into the full positional parameter list. `null` for
  /// named parameters. Used to compare against the maximum positional
  /// argument count observed at any call site.
  final int? positionalIndex;
}

/// Argument usage observed at all call sites of a single simple name,
/// aggregated across the workspace. Used to drive the
/// `unused_parameter_optional` rule.
class CallSiteUsage {
  CallSiteUsage();

  /// Named argument labels observed at any call site.
  final Set<String> namedArgsPassed = <String>{};

  /// Highest positional argument count observed at any call site
  /// (excluding named arguments).
  int maxPositionalArgs = 0;

  void mergeNamed(String name) => namedArgsPassed.add(name);
  void mergePositional(int count) {
    if (count > maxPositionalArgs) maxPositionalArgs = count;
  }

  void mergeFrom(CallSiteUsage other) {
    namedArgsPassed.addAll(other.namedArgsPassed);
    if (other.maxPositionalArgs > maxPositionalArgs) {
      maxPositionalArgs = other.maxPositionalArgs;
    }
  }
}

/// A single declaration extracted from a Dart source file.
///
/// Holds the metadata needed to:
/// - identify the declaration in reports (name, kind, location),
/// - participate in reachability graph BFS (`outgoingNames`,
///   `enclosingTypeName`),
/// - decide whether the declaration should be kept alive
///   (`annotations`, `isPublic`).
class DeclarationRecord {
  DeclarationRecord({
    required this.name,
    required this.kind,
    required this.packageName,
    required this.libraryPath,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.isPublic,
    required this.outgoingNames,
    required this.annotations,
    this.enclosingTypeName,
    this.unusedParameters = const [],
    this.optionalParameters = const [],
  });

  /// The simple name (no library prefix) of the declaration.
  final String name;

  final DeclarationKind kind;

  /// The pub package this declaration belongs to.
  final String packageName;

  /// Absolute path of the library file containing the declaration.
  final String libraryPath;

  final int offset;
  final int length;
  final int line;
  final int column;

  /// `true` if the name does not start with `_`.
  final bool isPublic;

  /// Simple names referenced inside the declaration body. Used as outgoing
  /// edges in the reachability graph.
  final Set<String> outgoingNames;

  /// Annotation simple names attached to the declaration
  /// (e.g. `visibleForTesting`, `internal`, `RoutePage`).
  final Set<String> annotations;

  /// For methods / fields / getters / setters: the enclosing class or
  /// extension name. `null` for top-level declarations.
  final String? enclosingTypeName;

  /// Parameters declared by this callable that are never referenced in
  /// its body or constructor initializers. Empty for non-callable kinds
  /// and for callables that have been intentionally excluded from the
  /// `unused_parameter` analysis (overrides, abstract / external / native
  /// bodies, operators).
  final List<ParameterRecord> unusedParameters;

  /// All optional parameters declared by this callable (named and
  /// positional), regardless of whether their bodies use them. Empty
  /// for non-callable kinds and for callables intentionally excluded
  /// from the `unused_parameter_optional` analysis (overrides, abstract
  /// / external / native bodies, operators, `UnimplementedError` stubs).
  final List<OptionalParameterRecord> optionalParameters;

  /// A stable identifier suitable for baseline diffing and SARIF
  /// `partialFingerprints`.
  String get stableId =>
      '$packageName|$libraryPath|${enclosingTypeName ?? ''}|$name|${kind.name}';
}
