import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/assets/flutter_assets.dart';
import 'package:kareki/src/l10n/ast_values.dart';

/// Records generated member dependencies separately from user references.
/// Only strings/ids survive resolution; analyzer elements and ASTs do not.
class AssetUsage {
  AssetUsage(this.assets);

  final List<FlutterAsset> assets;
  final used = <String>{};
  final warnings = <String>{};
  final _references = <String>{};
  final _edges = <String, Set<String>>{};
  final _resources = <String, Set<String>>{};
  final _members = <String, Set<String>>{};
  final _containers = <String, Set<String>>{};
  final _escapedTypes = <String>{};

  String? _id(Element? element) {
    if (element == null) return null;
    final base = element.nonSynthetic.baseElement;
    final source = base.firstFragment.libraryFragment?.source.fullName;
    final offset = base.firstFragment.nameOffset;
    return '$source|${base.enclosingElement?.name}|${base.name}|$offset';
  }

  String? _classId(DartType? type) =>
      type is InterfaceType ? _id(type.element) : null;

  late final Map<String, Set<String>> _paths = _indexPaths();

  Map<String, Set<String>> _indexPaths() {
    final result = <String, Set<String>>{};
    for (final asset in assets) {
      for (final key in [
        '${asset.packageName}|${asset.name}',
        'packages/${asset.packageName}/${asset.name}',
      ]) {
        result.putIfAbsent(key, () => {}).add(asset.id);
      }
    }
    return result;
  }

  Set<String> _matches(String value, String packageName) {
    // Directly requested density variants also retain the logical image.
    final logical = value.replaceAll(RegExp(r'/\d+(?:\.\d+)?x/'), '/');
    return {
      for (final path in {value, logical}) ...{
        ...?_paths['$packageName|$path'],
        ...?_paths[path],
        if (packageName == '*')
          for (final asset in assets)
            if (asset.name == path) asset.id,
      },
    };
  }

  void visit(
    String path,
    String packageName,
    CompilationUnit unit, {
    required bool generated,
  }) {
    unit.accept(_AssetVisitor(this, path, packageName, generated: generated));
  }

  void finish() {
    // Container values passed/returned to opaque consumers may be enumerated.
    // Expand only those containers, never an intermediate Assets.images access.
    final types = _escapedTypes.toList();
    final seenTypes = <String>{};
    while (types.isNotEmpty) {
      final type = types.removeLast();
      if (!seenTypes.add(type)) continue;
      _references.addAll(_members[type] ?? const {});
      types.addAll(_containers[type] ?? const {});
    }
    final pending = _references.toList();
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!seen.add(id)) continue;
      used.addAll(_resources[id] ?? const {});
      pending.addAll(_edges[id] ?? const {});
    }
  }
}

class _AssetVisitor extends RecursiveAstVisitor<void> {
  _AssetVisitor(
    this.usage,
    this.path,
    this.packageName, {
    required this.generated,
  });

  final AssetUsage usage;
  final String path;
  final String packageName;
  final bool generated;
  String? _owner;

  String _argumentPackage(AstNode node) {
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent is ArgumentList) {
        for (final argument in parent.arguments) {
          if (l10nValueName(argument) == 'package' ||
              l10nValueName(argument) == 'fontPackage') {
            final expression = l10nValueExpression(argument);
            return expression == null ? '*' : _value(expression) ?? '*';
          }
        }
        break;
      }
      if (parent is Statement || parent is Declaration) break;
    }
    return packageName;
  }

  void _record(String value, {String? ownerPackage}) {
    final matches = usage._matches(value, ownerPackage ?? packageName);
    if (generated) {
      if (_owner != null) {
        usage._resources.putIfAbsent(_owner!, () => {}).addAll(matches);
      }
    } else {
      usage.used.addAll(matches);
    }
  }

  void _declaration(Element? element, DartType? type, void Function() visit) {
    final previous = _owner;
    _owner = usage._id(element);
    if (generated && _owner != null) {
      final host = usage._id(element?.enclosingElement);
      if (host != null) {
        usage._members.putIfAbsent(host, () => {}).add(_owner!);
        final container = usage._classId(type);
        if (container != null) {
          usage._containers.putIfAbsent(host, () => {}).add(container);
        }
      }
    }
    if (element is VariableElement && element.isConst) {
      final value = element.computeConstantValue()?.toStringValue();
      if (value != null) _record(value);
    }
    visit();
    _owner = previous;
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    _declaration(
      element,
      element?.returnType,
      () => super.visitMethodDeclaration(node),
    );
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final element = node.declaredFragment?.element;
    _declaration(
      element,
      element?.type,
      () => super.visitVariableDeclaration(node),
    );
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    _record(
      node.value,
      ownerPackage: generated ? packageName : _argumentPackage(node),
    );
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    final value = node.stringValue;
    if (value != null) _record(value, ownerPackage: _argumentPackage(node));
    super.visitAdjacentStrings(node);
  }

  @override
  void visitPatternField(PatternField node) {
    final id = usage._id(node.element);
    if (!generated && id != null) usage._references.add(id);
    super.visitPatternField(node);
  }

  String? _value(Expression expression) {
    if (expression is StringLiteral) return expression.stringValue;
    if (expression is ParenthesizedExpression) {
      return _value(expression.expression);
    }
    if (expression is BinaryExpression && expression.operator.lexeme == '+') {
      final left = _value(expression.leftOperand);
      final right = _value(expression.rightOperand);
      if (left != null && right != null) return left + right;
    }
    final element = switch (expression) {
      SimpleIdentifier() => expression.element,
      PrefixedIdentifier() => expression.identifier.element,
      PropertyAccess() => expression.propertyName.element,
      _ => null,
    };
    final variable = element is PropertyAccessorElement
        ? element.variable
        : element;
    if (variable is VariableElement && variable.isConst) {
      return variable.computeConstantValue()?.toStringValue();
    }
    return null;
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final value = _value(node);
    if (value != null) _record(value, ownerPackage: _argumentPackage(node));
    super.visitBinaryExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext() &&
        node.parent is! Combinator &&
        node.parent is! Label) {
      final id = usage._id(node.element);
      if (id != null) {
        if (generated) {
          if (_owner != null) {
            usage._edges.putIfAbsent(_owner!, () => {}).add(id);
          }
        } else {
          usage._references.add(id);
          final value = _value(node);
          if (value != null) {
            _record(value, ownerPackage: _argumentPackage(node));
          }
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (!generated) {
      final buffer = StringBuffer();
      var known = true;
      for (final element in node.elements) {
        if (element is InterpolationString) {
          buffer.write(element.value);
        } else if (element is InterpolationExpression) {
          final value = _value(element.expression);
          if (value == null) {
            known = false;
            break;
          }
          buffer.write(value);
        }
      }
      if (known) {
        _record(buffer.toString());
      } else if (buffer.isNotEmpty) {
        final prefix = buffer.toString();
        final retained = {
          for (final asset in usage.assets)
            if (!asset.font &&
                ((asset.packageName == packageName &&
                        asset.name.startsWith(prefix)) ||
                    'packages/${asset.packageName}/${asset.name}'.startsWith(
                      prefix,
                    )))
              asset.id,
        };
        if (retained.isNotEmpty) {
          usage.used.addAll(retained);
          usage.warnings.add(
            'Dynamic asset path at $path:${node.offset}; matching assets retained conservatively.',
          );
        }
      }
    }
    super.visitStringInterpolation(node);
  }

  void _escape(Expression expression) {
    if (generated) return;
    final type = usage._classId(expression.staticType);
    if (type != null) usage._escapedTypes.add(type);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    for (final argument in node.arguments) {
      // NamedExpression was renamed in newer analyzer releases. Its child
      // expression shape remains shared by supported versions.
      final expression = l10nValueExpression(argument);
      if (expression != null) _escape(expression);
    }
    super.visitArgumentList(node);
  }

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.expression != null) _escape(node.expression!);
    super.visitReturnStatement(node);
  }

  @override
  void visitExpressionFunctionBody(ExpressionFunctionBody node) {
    _escape(node.expression);
    super.visitExpressionFunctionBody(node);
  }

  @override
  void visitCommentReference(CommentReference node) {}
}
