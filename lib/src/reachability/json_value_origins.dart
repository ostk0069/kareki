import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/reachability/external_decoder_models.dart';

/// A deliberately closed, read-only subset of modeled decoder value flow.
///
/// This proves only that an index cannot dispatch to a workspace declaration,
/// not that decoded data has the expected shape or that access cannot throw.
/// Keep this object local to a resolved unit; it holds ASTs, unlike graph data.
class JsonValueOrigins extends RecursiveAstVisitor<void> {
  JsonValueOrigins(CompilationUnit unit, this.models) {
    unit.accept(this);
  }

  final ExternalDecoderModels models;
  final _variables = <Element, VariableDeclaration>{};
  final _iterations = <Element, ForEachPartsWithDeclaration>{};
  final _references = <Element, List<SimpleIdentifier>>{};
  final _closed = <MethodInvocation, bool>{};
  final _kinds = <MethodInvocation, DecodedValueKind>{};

  @override
  void visitForEachPartsWithDeclaration(ForEachPartsWithDeclaration node) {
    final element = node.loopVariable.declaredFragment?.element;
    if (element is LocalVariableElement &&
        element.isFinal &&
        node.parent is ForStatement &&
        (node.parent as ForStatement).awaitKeyword == null) {
      _iterations[element.baseElement] = node;
    }
    super.visitForEachPartsWithDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element is LocalVariableElement && element.isFinal) {
      _variables[element.baseElement] = node;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element;
    if (element is LocalVariableElement && !node.inDeclarationContext()) {
      _references.putIfAbsent(element.baseElement, () => []).add(node);
    }
    super.visitSimpleIdentifier(node);
  }

  bool isDecodedIndex(IndexExpression node) {
    if (!_readIndex(node)) return false;
    final root = _origin(node.realTarget, {});
    return root != null &&
        _closed.putIfAbsent(root, () => _closedUse(root, root, {}));
  }

  MethodInvocation? _origin(Expression? node, Set<Element> seen) {
    if (node is MethodInvocation && _isDecode(node)) return node;
    if (node is SimpleIdentifier) {
      final element = node.element?.baseElement;
      if (element == null || !seen.add(element)) return null;
      if (_iterations[element] case final loop?) {
        return _origin(loop.iterable, seen);
      }
      return _origin(_variables[element]?.initializer, seen);
    }
    if (node is ParenthesizedExpression) return _origin(node.expression, seen);
    if (node is AsExpression) {
      // Verify the origin before consulting an external type model. Otherwise
      // a prior unrelated YAML call could change which casts are recognized.
      final root = _origin(node.expression, seen);
      return root != null && _jsonCast(node.type.type) ? root : null;
    }
    if (node is PostfixExpression && node.operator.lexeme == '!') {
      return _origin(node.operand, seen);
    }
    if (node is IndexExpression) {
      final root = _origin(node.realTarget, seen);
      return root != null && _readIndex(node) ? root : null;
    }
    return null;
  }

  bool _isDecode(MethodInvocation node) {
    // Even an explicitly supplied null reviver is left unsupported initially.
    // A JsonCodec receiver's type alone cannot rule out a stored reviver.
    if (node.isCascaded || node.argumentList.arguments.length != 1) {
      return false;
    }
    final method = node.methodName.element?.baseElement;
    final sdk = _inLibrary(method, 'dart:convert');
    final external = sdk ? null : models.kindOf(method);
    if (!sdk && external == null) return false;
    if (method is TopLevelFunctionElement &&
        (sdk && method.name == 'jsonDecode' || external != null)) {
      _kinds[node] = external ?? DecodedValueKind.json;
      return true;
    }
    if (method is! MethodElement ||
        method.name != 'decode' ||
        method.enclosingElement?.name != (sdk ? 'JsonCodec' : 'JsoncCodec')) {
      return false;
    }
    var receiver = node.realTarget;
    while (receiver is ParenthesizedExpression) {
      receiver = receiver.expression;
    }
    final getter = switch (receiver) {
      SimpleIdentifier() => receiver.element,
      PrefixedIdentifier() => receiver.identifier.element,
      PropertyAccess() => receiver.propertyName.element,
      _ => null,
    };
    final valid =
        getter is GetterElement &&
        getter.variable is TopLevelVariableElement &&
        getter.name == (sdk ? 'json' : 'jsonc') &&
        getter.library == method.library;
    if (valid) _kinds[node] = DecodedValueKind.json;
    return valid;
  }

  bool _closedUse(AstNode value, MethodInvocation root, Set<Element> aliases) {
    final parent = value.parent;
    if (parent is ParenthesizedExpression ||
        parent is PostfixExpression && parent.operator.lexeme == '!') {
      return _closedUse(parent!, root, aliases);
    }
    if (parent is AsExpression && _jsonCast(parent.type.type)) {
      // A successful cast to an immutable scalar cannot leak a container.
      if (_scalar(parent.type.type)) return true;
      return _closedUse(parent, root, aliases);
    }
    if (parent is IndexExpression &&
        parent.target == value &&
        _readIndex(parent)) {
      return _closedUse(parent, root, aliases);
    }
    if (parent is PropertyAccess && parent.target == value) {
      final getter = parent.propertyName.element;
      // JSON map keys are strings, so even an escaping keys view cannot expose
      // mutable descendants. Other getters/methods may leak or mutate them.
      if (_safeKeys(getter, root)) {
        return true;
      }
    }
    if (parent is PrefixedIdentifier &&
        parent.prefix == value &&
        _safeKeys(parent.identifier.element, root)) {
      return true;
    }
    if (parent is BinaryExpression &&
        {'==', '!='}.contains(parent.operator.lexeme) &&
        (parent.leftOperand is NullLiteral ||
            parent.rightOperand is NullLiteral)) {
      return true;
    }
    if (parent is ForEachPartsWithDeclaration && parent.iterable == value) {
      final element = parent.loopVariable.declaredFragment?.element.baseElement;
      if (!_iterations.containsKey(element)) return false;
      // Only a core List (possibly cast/promoted) is known to iterate values.
      // A custom Iterable could return unrelated values or mutate the tree.
      final type = parent.iterable.staticType;
      if (type is! InterfaceType ||
          !_inLibrary(type.element, 'dart:core') ||
          type.element.name != 'List') {
        return false;
      }
      return _closedReferences(element!, root, aliases);
    }
    if (parent is VariableDeclaration && parent.initializer == value) {
      final element = parent.declaredFragment?.element.baseElement;
      if (!_variables.containsKey(element)) {
        return false;
      }
      // A full-unit reference check deliberately rejects capture, storage,
      // return, argument passing, writes and unsupported aliases, even when
      // they occur after the read. No control-flow ordering is assumed.
      return _closedReferences(element!, root, aliases);
    }
    return false;
  }

  bool _closedReferences(
    Element element,
    MethodInvocation root,
    Set<Element> aliases,
  ) {
    if (!aliases.add(element)) return false;
    return (_references[element] ?? []).every(
      (reference) =>
          reference.thisOrAncestorOfType<FunctionBody>() ==
              root.thisOrAncestorOfType<FunctionBody>() &&
          _closedUse(reference, root, aliases),
    );
  }

  bool _safeKeys(Element? getter, MethodInvocation root) {
    if (getter is! GetterElement || getter.name != 'keys') return false;
    if (_kinds[root] == DecodedValueKind.yaml) {
      // The reviewed loader constructs read-only YamlMap/YamlList containers.
      // YAML keys may themselves be containers, unlike JSON's string keys.
      return models.isYamlNodeElement(getter) &&
          getter.enclosingElement.name == 'YamlMap';
    }
    return _inLibrary(getter, 'dart:core') &&
        getter.enclosingElement.name == 'Map';
  }

  bool _readIndex(IndexExpression node) {
    if (node.isCascaded) return false;
    final parent = node.parent;
    if (parent is AssignmentExpression && parent.leftHandSide == node ||
        parent is PrefixExpression &&
            {'++', '--'}.contains(parent.operator.lexeme) ||
        parent is PostfixExpression &&
            {'++', '--'}.contains(parent.operator.lexeme)) {
      return false;
    }
    final element = node.element;
    return element == null ||
        _inLibrary(element, 'dart:core') &&
            {
              'Map',
              'List',
              'String',
            }.contains(element.enclosingElement?.name) ||
        models.isYamlNodeElement(element) &&
            {'YamlMap', 'YamlList'}.contains(element.enclosingElement?.name);
  }

  bool _jsonCast(DartType? type) =>
      _scalar(type) ||
      type is InterfaceType &&
          _inLibrary(type.element, 'dart:core') &&
          {'Map', 'List'}.contains(type.element.name) ||
      type is InterfaceType &&
          models.isYamlNodeElement(type.element) &&
          {'YamlMap', 'YamlList'}.contains(type.element.name);

  bool _scalar(DartType? type) =>
      type is InterfaceType &&
      _inLibrary(type.element, 'dart:core') &&
      {
        'String',
        'bool',
        'num',
        'int',
        'double',
        'Null',
      }.contains(type.element.name);

  bool _inLibrary(Element? element, String uri) =>
      element?.library?.uri.toString() == uri;
}
