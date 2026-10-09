/// Phase A experiment: resolved bindings, not a production reachability engine.
///
/// Only public analyzer APIs are used. No element objects escape the adapter,
/// and no changes to kareki's runner, findings, or baseline IDs are required.
library;

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:path/path.dart' as p;

/// Execution-local identity. Offsets deliberately do not become baseline IDs.
///
/// Both the owning library and physical unit matter: a part belongs to a
/// library, and two libraries can (even erroneously) include the same part.
typedef ProbeId = ({
  String libraryPath,
  String unitPath,
  int offset,
  String kind,
  String? name,
});

ProbeId? _identity(Element? input) {
  if (input == null) return null;
  var element = input.baseElement;
  // Reads and writes of a field target induced accessors. Explicit accessors
  // remain separate declarations; only induced ones map back to the field.
  if (element is PropertyAccessorElement) {
    element = element.nonSynthetic.baseElement;
  }
  final fragment = element.firstFragment;
  final source = fragment.libraryFragment?.source;
  final library = element.library;
  if (source == null || library == null) return null;
  return (
    libraryPath: p.normalize(library.firstFragment.source.fullName),
    unitPath: p.normalize(source.fullName),
    offset: fragment.offset,
    kind: element.kind.name,
    name: element.lookupName,
  );
}

class ProbeDeclaration {
  const ProbeDeclaration(this.id, this.label);

  final ProbeId id;
  final String label;
}

class ProbeReference {
  const ProbeReference({
    required this.path,
    required this.offset,
    required this.spelling,
    required this.target,
    required this.owner,
  });

  final String path;
  final int offset;
  final String spelling;

  /// Null means unresolved, not proof that no declaration is referenced.
  final ProbeId? target;
  final ProbeId? owner;
}

class ProbeDiagnostic {
  const ProbeDiagnostic(this.path, this.code, this.severity);

  final String path;
  final String code;
  final String severity;
}

class ProbeSnapshot {
  final declarations = <ProbeId, ProbeDeclaration>{};
  final references = <ProbeReference>[];
  final diagnostics = <ProbeDiagnostic>[];
  final unresolvedFiles = <String>[];
  final contextRoots = <String>{};
}

/// Resolves only the requested units, using their real package configurations.
///
/// This intentionally does not guess package mappings, run pub get, decide
/// roots, expand virtual dispatch, or turn unresolved references into findings.
Future<ProbeSnapshot> resolveProbe({
  required List<String> includedPaths,
  required List<String> files,
  ResourceProvider? resourceProvider,
}) async {
  final collection = AnalysisContextCollection(
    includedPaths: includedPaths.map(p.normalize).toList(),
    resourceProvider: resourceProvider,
  );
  final snapshot = ProbeSnapshot();
  try {
    for (final path in files) {
      final normalized = p.normalize(path);
      final matching = collection.contexts.where(
        (context) => context.contextRoot.isAnalyzed(normalized),
      );
      final owners =
          collection.contexts
              .where(
                (context) => context.contextRoot.includedPaths.any(
                  (root) => root == normalized || p.isWithin(root, normalized),
                ),
              )
              .toList()
            ..sort(
              (a, b) => b.contextRoot.root.path.length.compareTo(
                a.contextRoot.root.path.length,
              ),
            );
      final context = matching.isNotEmpty
          ? collection.contextFor(normalized)
          : owners.first;
      snapshot.contextRoots.add(context.contextRoot.root.path);
      final result = await context.currentSession.getResolvedUnit(normalized);
      if (result is! ResolvedUnitResult) {
        snapshot.unresolvedFiles.add(normalized);
        continue;
      }
      for (final diagnostic in result.diagnostics) {
        snapshot.diagnostics.add(
          ProbeDiagnostic(
            normalized,
            diagnostic.diagnosticCode.lowerCaseName,
            diagnostic.diagnosticCode.severity.name,
          ),
        );
      }
      result.unit.accept(_BindingVisitor(normalized, snapshot));
    }
  } finally {
    await collection.dispose();
  }
  return snapshot;
}

class _BindingVisitor extends GeneralizingAstVisitor<void> {
  _BindingVisitor(this.path, this.snapshot);

  final String path;
  final ProbeSnapshot snapshot;
  ProbeId? _owner;

  @override
  void visitNode(AstNode node) {
    final previousOwner = _owner;
    if (node is Declaration) {
      final element = node.declaredFragment?.element;
      final id = _identity(element);
      if (id != null && element != null) {
        snapshot.declarations[id] = ProbeDeclaration(id, _label(element));
        _owner = id;
      }
    }
    super.visitNode(node);
    _owner = previousOwner;
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext()) {
      final assignment = _assignmentFor(node);
      if (assignment == null) {
        _reference(node.element, node.offset, node.name);
      } else {
        // A write's binding lives on the enclosing expression, not always on
        // SimpleIdentifier.element. Compound assignments consume both sides.
        final elements = {assignment.readElement, assignment.writeElement}
          ..remove(null);
        if (elements.isEmpty) {
          _reference(null, node.offset, node.name);
        } else {
          for (final element in elements) {
            _reference(element, node.offset, node.name);
          }
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    // void and dynamic legitimately have no declaration.
    if (node.element != null ||
        !{'void', 'dynamic'}.contains(node.name.lexeme)) {
      _reference(node.element, node.name.offset, node.name.lexeme);
    }
    super.visitNamedType(node);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _reference(node.element, node.offset, node.toSource());
    super.visitConstructorName(node);
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _reference(node.element, node.offset, node.toSource());
    super.visitSuperConstructorInvocation(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    _reference(node.element, node.offset, node.toSource());
    super.visitRedirectingConstructorInvocation(node);
  }

  @override
  void visitCommentReference(CommentReference node) {
    // Documentation references are outside this code-reference experiment.
  }

  CompoundAssignmentExpression? _assignmentFor(SimpleIdentifier identifier) {
    AstNode node = identifier;
    while (true) {
      final parent = node.parent;
      if (parent is PrefixedIdentifier && parent.identifier == node ||
          parent is PropertyAccess && parent.propertyName == node) {
        node = parent!;
      } else if (parent is AssignmentExpression &&
          parent.leftHandSide == node) {
        return parent;
      } else if (parent is PostfixExpression && parent.operand == node) {
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

  void _reference(Element? element, int offset, String spelling) {
    snapshot.references.add(
      ProbeReference(
        path: path,
        offset: offset,
        spelling: spelling,
        target: _identity(element),
        owner: _owner,
      ),
    );
  }

  String _label(Element element) {
    final names = <String>[];
    Element? current = element;
    while (current != null && current is! LibraryElement) {
      names.add(current.lookupName ?? '<unnamed>');
      current = current.enclosingElement;
    }
    return names.reversed.join('.');
  }
}
