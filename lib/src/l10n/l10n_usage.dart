import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/l10n/flutter_l10n.dart';

/// Collects resolved member uses separately from generated reachability roots.
/// Analyzer objects stay inside this execution-local collector.
class L10nUsage {
  L10nUsage(this.families, this.canonical, this.workspacePaths);

  final List<FlutterL10n> families;
  final String Function(String) canonical;
  final Set<String> workspacePaths;
  final used = <FlutterL10n, Set<String>>{};
  final warnings = <String>{};
  final _validated = <FlutterL10n>{};

  String? _path(Element? element) {
    final source = element?.firstFragment.libraryFragment?.source;
    return source == null ? null : canonical(source.fullName);
  }

  bool _root(ClassElement type, FlutterL10n family) =>
      type.name == family.className &&
      _path(type) == canonical(family.outputPath);

  Iterable<FlutterL10n> _families(ClassElement type) sync* {
    for (final family in families) {
      if (_root(type, family) ||
          type.allSupertypes.any(
            (t) =>
                t.element is ClassElement &&
                _root(t.element as ClassElement, family),
          )) {
        yield family;
      }
    }
  }

  Iterable<FlutterL10n> _types(DartType? type, [Set<DartType>? seen]) sync* {
    if (type == null) return;
    final visited = seen ?? <DartType>{};
    if (!visited.add(type)) return;
    if (type is InterfaceType) {
      final element = type.element;
      if (element is ClassElement) yield* _families(element);
      for (final argument in type.typeArguments) {
        yield* _types(argument, visited);
      }
    } else if (type is FunctionType) {
      yield* _types(type.returnType, visited);
    } else if (type is TypeParameterType) {
      yield* _types(type.bound, visited);
    }
  }

  void visit(String path, CompilationUnit unit) {
    unit.accept(_L10nVisitor(this, path));
  }

  void _validate(ClassElement type) {
    for (final family in families) {
      if (!_root(type, family)) continue;
      final names = {
        for (final getter in type.getters)
          if (!getter.isStatic &&
              getter.nonSynthetic is GetterElement &&
              getter.returnType.isDartCoreString)
            getter.name!,
        for (final method in type.methods)
          if (!method.isStatic && method.returnType.isDartCoreString)
            method.name!,
      };
      final expected = family.keys.keys.toSet();
      final missing = expected.difference(names);
      final extra = names.difference(expected);
      if (missing.isNotEmpty || extra.isNotEmpty) {
        throw FormatException(
          '${family.outputPath}: Translation API does not match ${family.templatePath}; '
          'missing: ${missing.toList()..sort()}, extra: ${extra.toList()..sort()}. Run flutter gen-l10n.',
        );
      }
      _validated.add(family);
    }
  }

  void finish() {
    for (final family in families) {
      if ((family.keys.isNotEmpty || File(family.outputPath).existsSync()) &&
          !_validated.contains(family)) {
        throw FormatException(
          '${family.outputPath}: Generated class ${family.className} was not resolved. Run flutter gen-l10n.',
        );
      }
    }
  }

  void _reference(
    Element? element,
    String name,
    Expression? receiver,
    String site,
  ) {
    final host = element?.baseElement.enclosingElement;
    if (host is ClassElement &&
        (element is GetterElement || element is MethodElement)) {
      for (final family in _families(host)) {
        if (family.keys.containsKey(name)) {
          used.putIfAbsent(family, () => {}).add(name);
        }
      }
    } else if (element == null && receiver != null) {
      final candidates = _types(receiver.staticType).toSet();
      // A dynamic receiver has no reliable resource identity. Retain only
      // matching keys across all families, rather than guessing by name.
      final uncertain = candidates.isNotEmpty
          ? candidates
          : receiver.staticType is DynamicType
          ? families
          : const <FlutterL10n>[];
      for (final family in uncertain) {
        if (!family.keys.containsKey(name)) continue;
        used.putIfAbsent(family, () => {}).add(name);
        warnings.add(
          'Localization use of ${family.className}.$name is uncertain at $site; key retained conservatively.',
        );
      }
    }
  }

  void _escape(DartType? type, String site) {
    for (final family in _types(type).toSet()) {
      used.putIfAbsent(family, () => {}).addAll(family.keys.keys);
      warnings.add(
        'Localization instance ${family.className} escapes to an unknown consumer at $site; keys retained conservatively.',
      );
    }
  }
}

class _L10nVisitor extends RecursiveAstVisitor<void> {
  _L10nVisitor(this.usage, this.path);

  final L10nUsage usage;
  final String path;

  bool get _generated => usage.families.any(
    (family) =>
        family.outputPaths.any((output) => usage.canonical(output) == path),
  );

  String _site(AstNode node) {
    final location = (node.root as CompilationUnit).lineInfo.getLocation(
      node.offset,
    );
    return '$path:${location.lineNumber}:${location.columnNumber}';
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) usage._validate(element);
    super.visitClassDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (!_generated &&
        !node.inDeclarationContext() &&
        node.parent is! Label &&
        node.parent is! Combinator) {
      final receiver = switch (node.parent) {
        final PrefixedIdentifier parent when parent.identifier == node =>
          parent.prefix,
        final PropertyAccess parent when parent.propertyName == node =>
          parent.realTarget,
        final MethodInvocation parent when parent.methodName == node =>
          parent.realTarget,
        _ => null,
      };
      usage._reference(node.element, node.name, receiver, _site(node));
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitCommentReference(CommentReference node) {}

  @override
  void visitPatternField(PatternField node) {
    if (!_generated) {
      usage._reference(
        node.element,
        node.effectiveName ?? '',
        null,
        _site(node),
      );
    }
    super.visitPatternField(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    if (!_generated) {
      final callee = switch (node.parent) {
        final MethodInvocation parent => parent.methodName.element,
        final InstanceCreationExpression parent =>
          parent.constructorName.element,
        _ => null,
      };
      final knownCallable =
          callee is TopLevelFunctionElement ||
          callee is ConstructorElement ||
          callee is MethodElement;
      final hasBody =
          callee is ExecutableElement &&
          !callee.isExternal &&
          !(callee is MethodElement && callee.isAbstract);
      if (!knownCallable ||
          !hasBody ||
          !usage.workspacePaths.contains(usage._path(callee))) {
        for (final argument in node.arguments) {
          final AstNode value = argument;
          final expression = value is Expression
              ? value
              : value.childEntities.whereType<Expression>().firstOrNull;
          if (expression != null) {
            usage._escape(expression.staticType, _site(expression));
            if (expression is AsExpression) {
              usage._escape(
                expression.expression.staticType,
                _site(expression),
              );
            }
          }
        }
      }
    }
    super.visitArgumentList(node);
  }
}
