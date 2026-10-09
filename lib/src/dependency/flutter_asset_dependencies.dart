import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Flutter's IconData can refer to a font package without importing that
/// package. Read resolved constant values, including SDK constants/re-exports,
/// rather than exempting particular dependency or identifier names.
class FlutterAssetDependencies extends RecursiveAstVisitor<void> {
  FlutterAssetDependencies(this.packages);

  final Set<String> packages;

  bool _isIconData(InterfaceElement type) =>
      type.name == 'IconData' &&
      type.library.uri.toString() ==
          'package:flutter/src/widgets/icon_data.dart';

  void _record(DartObject? value) {
    final type = value?.type;
    if (type is! InterfaceType || !_isIconData(type.element)) return;
    final package = value!.getField('fontPackage')?.toStringValue();
    if (package != null && package.isNotEmpty) packages.add(package);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!node.inDeclarationContext()) {
      final element = node.element;
      final variable = element is PropertyAccessorElement
          ? element.variable
          : element;
      if (variable is VariableElement && variable.isConst) {
        final type = variable.type;
        if (type is InterfaceType && _isIconData(type.element)) {
          _record(variable.computeConstantValue());
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.element?.enclosingElement;
    if (type != null && _isIconData(type)) {
      for (final argument in node.argumentList.arguments) {
        // This token/child form is shared by supported analyzer versions.
        if (argument.beginToken.lexeme != 'fontPackage' ||
            argument.beginToken.next?.lexeme != ':') {
          continue;
        }
        for (final child in argument.childEntities.whereType<Expression>()) {
          final package = child is StringLiteral ? child.stringValue : null;
          if (package != null && package.isNotEmpty) packages.add(package);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }
}
