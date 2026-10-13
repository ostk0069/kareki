import 'package:analyzer/dart/ast/ast.dart';

// analyzer 14 split arguments/record fields from Expressions. The token and
// child contracts below also cover analyzer 10's NamedExpression nodes.
String? l10nValueName(AstNode node) =>
    node.beginToken.next?.lexeme == ':' ? node.beginToken.lexeme : null;

Expression? l10nValueExpression(AstNode node) =>
    node is Expression && l10nValueName(node) == null
    ? node
    : node.childEntities.whereType<Expression>().firstOrNull;
