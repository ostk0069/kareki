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

  /// A stable identifier suitable for baseline diffing and SARIF
  /// `partialFingerprints`.
  String get stableId =>
      '$packageName|$libraryPath|${enclosingTypeName ?? ''}|$name|${kind.name}';
}
