import 'package:kareki/src/model/declaration.dart';

/// Index of declarations keyed by simple name, with outgoing edges for BFS.
class DeclarationIndex {
  DeclarationIndex._(this._byName, this._allDeclarations, this._enclosingType);

  /// Build an index from a flat list of records.
  factory DeclarationIndex.fromRecords(Iterable<DeclarationRecord> records) {
    final byName = <String, List<DeclarationRecord>>{};
    final all = <DeclarationRecord>[];
    // (packageName, libraryPath, typeName) -> the type's declaration.
    final enclosingType = <String, DeclarationRecord>{};
    for (final record in records) {
      byName.putIfAbsent(record.name, () => []).add(record);
      all.add(record);
      if (record.enclosingTypeName == null) {
        final key =
            '${record.packageName}|${record.libraryPath}|'
            '${record.name}';
        enclosingType[key] = record;
      }
    }
    return DeclarationIndex._(byName, all, enclosingType);
  }

  final Map<String, List<DeclarationRecord>> _byName;
  final List<DeclarationRecord> _allDeclarations;
  final Map<String, DeclarationRecord> _enclosingType;

  Iterable<DeclarationRecord> get all => _allDeclarations;

  /// All declarations with the given simple name. Same-name homonyms across
  /// packages all flow together — this is the dartrics-style simple-name
  /// over-approximation that trades precision for analyzer-version
  /// independence.
  List<DeclarationRecord> byName(String name) =>
      _byName[name] ?? const <DeclarationRecord>[];

  /// The enclosing type declaration for [member], if recorded.
  ///
  /// Returns the class/extension/mixin/enum declaration that lexically
  /// contains [member]. Members are paired with their enclosing type via
  /// the same `(packageName, libraryPath, typeName)` triple they share.
  DeclarationRecord? enclosingType(DeclarationRecord member) {
    final typeName = member.enclosingTypeName;
    if (typeName == null) return null;
    return _enclosingType['${member.packageName}|${member.libraryPath}|$typeName'];
  }
}

/// Computes the set of declarations reachable from a root simple-name set.
class ReachabilityBfs {
  /// Performs BFS from [roots] over [index].
  ///
  /// When [filter] is provided, declarations for which it returns false
  /// are NOT visited (they don't enter the reachable set, and their
  /// outgoing edges are not followed). Used by the `test_only_used`
  /// rule to compute "reachable from production only" — declarations
  /// in test source are filtered out so a production root named `main`
  /// doesn't transitively pull in test-only symbols via the same name
  /// declared in a test file.
  Set<DeclarationRecord> compute({
    required DeclarationIndex index,
    required Set<String> roots,
    bool Function(DeclarationRecord declaration)? filter,
  }) {
    final reachableRecords = <DeclarationRecord>{};
    final visitedNames = <String>{};
    final queue = <String>[...roots];

    while (queue.isNotEmpty) {
      final name = queue.removeLast();
      if (!visitedNames.add(name)) continue;

      for (final declaration in index.byName(name)) {
        if (filter != null && !filter(declaration)) continue;
        if (!reachableRecords.add(declaration)) continue;
        // When a member becomes reachable, its enclosing type
        // (class / mixin / extension / enum) is implicitly reachable too:
        // dispatch syntax `value.method()` references only the member's
        // simple name, never the extension/class identifier. Without this
        // edge an extension like `BoolExt` whose method `isTruthy` is
        // called via `someBool.isTruthy()` would be reported as unused.
        final enclosing = index.enclosingType(declaration);
        if (enclosing != null &&
            (filter == null || filter(enclosing)) &&
            reachableRecords.add(enclosing)) {
          for (final next in enclosing.outgoingNames) {
            if (!visitedNames.contains(next)) queue.add(next);
          }
        }
        for (final next in declaration.outgoingNames) {
          if (!visitedNames.contains(next)) queue.add(next);
        }
      }
    }
    return reachableRecords;
  }
}
