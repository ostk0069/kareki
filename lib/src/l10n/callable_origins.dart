import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/l10n/ast_values.dart';

/// A closed subset of local callable origins. Final bindings do not prove a
/// list immutable: every reference must remain a read-only record projection.
class L10nCallableOrigins extends RecursiveAstVisitor<void> {
  L10nCallableOrigins(CompilationUnit unit) {
    unit.accept(this);
  }

  final _variables = <Element, Expression>{};
  final _iterations = <Element, ForEachPartsWithDeclaration>{};
  final _references = <Element, List<SimpleIdentifier>>{};

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element is LocalVariableElement &&
        element.isFinal &&
        node.initializer != null) {
      _variables[element.baseElement] = node.initializer!;
    }
    super.visitVariableDeclaration(node);
  }

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
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final element = node.element?.baseElement;
    if (element != null && !node.inDeclarationContext()) {
      _references.putIfAbsent(element, () => []).add(node);
    }
    super.visitSimpleIdentifier(node);
  }

  /// All potential function values must be local function literals.
  bool isLocalCallback(Expression? expression) {
    final values = _values(expression, {});
    return values != null &&
        values.isNotEmpty &&
        values.every((value) => value is FunctionExpression);
  }

  /// Recover a concrete receiver without enumerating an open class hierarchy.
  MethodElement? concreteMethod(Expression? receiver, String name) {
    final values = _values(receiver, {});
    if (values == null || values.isEmpty) return null;
    MethodElement? method;
    for (final value in values) {
      if (value is! InstanceCreationExpression ||
          value.constructorName.element?.isFactory != false) {
        return null;
      }
      final type = value.staticType;
      if (type is! InterfaceType) return null;
      final candidate = type.element.getMethod(name);
      if (candidate == null || candidate.isAbstract) return null;
      if (method != null && method != candidate) return null;
      method = candidate;
    }
    return method;
  }

  List<Expression>? _values(Expression? expression, Set<Element> seen) {
    if (expression is ParenthesizedExpression) {
      return _values(expression.expression, seen);
    }
    if (expression is FunctionExpression ||
        expression is InstanceCreationExpression ||
        expression is RecordLiteral) {
      return [expression!];
    }
    if (expression is SimpleIdentifier) {
      final element = expression.element?.baseElement;
      if (element == null || !seen.add(element)) return null;
      final loop = _iterations[element];
      if (loop != null) {
        if (!_recordReads(element)) return null;
        return _iterable(loop.iterable, seen);
      }
      return _values(_variables[element], seen);
    }
    final (target, name) = switch (expression) {
      PropertyAccess() => (expression.realTarget, expression.propertyName.name),
      PrefixedIdentifier() => (expression.prefix, expression.identifier.name),
      _ => (null, ''),
    };
    if (target == null) return null;
    final records = _values(target, seen);
    if (records == null) return null;
    final result = <Expression>[];
    for (final record in records) {
      if (record is! RecordLiteral) return null;
      final field = record.fields
          .where((field) => l10nValueName(field) == name)
          .firstOrNull;
      final values = _values(
        field == null ? null : l10nValueExpression(field),
        {...seen},
      );
      if (values == null) return null;
      result.addAll(values);
    }
    return result;
  }

  List<Expression>? _iterable(Expression expression, Set<Element> seen) {
    if (expression is ParenthesizedExpression) {
      return _iterable(expression.expression, seen);
    }
    if (expression is SimpleIdentifier) {
      final element = expression.element?.baseElement;
      if (element == null || !seen.add(element)) return null;
      final value = _variables[element];
      if (value == null ||
          !(_references[element] ?? []).every(
            (reference) =>
                reference.parent is ForEachPartsWithDeclaration &&
                (reference.parent! as ForEachPartsWithDeclaration).iterable ==
                    reference,
          )) {
        return null;
      }
      return _iterable(value, seen);
    }
    if (expression is! ListLiteral ||
        expression.elements.isEmpty ||
        !expression.elements.every((value) => value is RecordLiteral)) {
      return null;
    }
    return expression.elements.cast<Expression>();
  }

  bool _recordReads(Element element) =>
      (_references[element] ?? []).every((reference) {
        final parent = reference.parent;
        return parent is PrefixedIdentifier && parent.prefix == reference ||
            parent is PropertyAccess && parent.realTarget == reference ||
            parent is MethodInvocation && parent.realTarget == reference;
      });

  /// A function-valued record field is represented as a method invocation.
  bool isRecordCallback(MethodInvocation invocation) {
    final target = invocation.realTarget;
    if (target == null) return false;
    final records = _values(target, {});
    if (records == null || records.isEmpty) return false;
    return records.every((record) {
      if (record is! RecordLiteral) return false;
      final field = record.fields
          .where((field) => l10nValueName(field) == invocation.methodName.name)
          .firstOrNull;
      return field != null && isLocalCallback(l10nValueExpression(field));
    });
  }
}
