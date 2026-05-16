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

  /// A stable identifier suitable for baseline diffing and SARIF
  /// `partialFingerprints`.
  String get stableId =>
      '$packageName|$libraryPath|${enclosingTypeName ?? ''}|$name|${kind.name}';
}
