import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/l10n/ast_values.dart';
import 'package:kareki/src/l10n/callable_origins.dart';
import 'package:kareki/src/l10n/consumer_models.dart';
import 'package:kareki/src/l10n/flutter_l10n.dart';
import 'package:kareki/src/model/localization_usage.dart';

/// Collects resolved member uses separately from generated reachability roots.
/// Analyzer objects stay inside this execution-local collector.
class L10nUsage {
  L10nUsage(this.families, this.canonical, this.workspacePaths);

  final List<FlutterL10n> families;
  final String Function(String) canonical;
  final Set<String> workspacePaths;
  final used = <FlutterL10n, Set<String>>{};
  final unknown = <FlutterL10n, Set<String>>{};
  late final Set<String> _keyNames = {
    for (final family in families) ...family.keys.keys,
  };
  late final Set<String> _generatedPaths = {
    for (final family in families)
      for (final path in family.outputPaths) canonical(path),
  };
  late final models = L10nConsumerModels(
    (path) => workspacePaths.contains(canonical(path)),
  );

  List<LocalizationUsage> get summaries => [
    for (final family in families)
      LocalizationUsage(
        packageName: family.packageName,
        templatePath: family.templatePath,
        used: used[family]?.length ?? 0,
        unknown: (unknown[family] ?? const <String>{})
            .difference(used[family] ?? const <String>{})
            .length,
        unused:
            family.keys.length - {...?used[family], ...?unknown[family]}.length,
      ),
  ];
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
    } else if (type is RecordType) {
      for (final field in [...type.positionalFields, ...type.namedFields]) {
        yield* _types(field.type, visited);
      }
    } else if (type is FunctionType) {
      yield* _types(type.returnType, visited);
    } else if (type is TypeParameterType) {
      yield* _types(type.bound, visited);
    }
  }

  void visit(String path, CompilationUnit unit) {
    unit.accept(_L10nVisitor(this, path, unit));
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
    AstNode node,
    String path,
  ) {
    if (!_keyNames.contains(name)) return;
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
        unknown.putIfAbsent(family, () => {}).add(name);
        warnings.add(
          'Localization use of ${family.className}.$name is uncertain at ${_site(node, path)}; key retained conservatively.',
        );
      }
    }
  }

  void _escape(Set<FlutterL10n> families, AstNode node, String path) {
    for (final family in families) {
      unknown.putIfAbsent(family, () => {}).addAll(family.keys.keys);
      warnings.add(
        'Localization instance ${family.className} escapes to an unknown consumer at ${_site(node, path)}; keys retained conservatively.',
      );
    }
  }

  String _site(AstNode node, String path) {
    final location = (node.root as CompilationUnit).lineInfo.getLocation(
      node.offset,
    );
    return '$path:${location.lineNumber}:${location.columnNumber}';
  }
}

class _L10nVisitor extends RecursiveAstVisitor<void> {
  _L10nVisitor(this.usage, this.path, this.unit);

  final L10nUsage usage;
  final String path;
  final CompilationUnit unit;
  // Index the whole unit only when a localization argument needs origin proof.
  late final origins = L10nCallableOrigins(unit);
  late final bool _generated = usage._generatedPaths.contains(path);

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
      usage._reference(node.element, node.name, receiver, node, path);
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
        node,
        path,
      );
    }
    super.visitPatternField(node);
  }

  bool _hasWorkspaceBody(Element? callee) =>
      (callee is TopLevelFunctionElement ||
          callee is ConstructorElement ||
          callee is MethodElement) &&
      callee is ExecutableElement &&
      !callee.isExternal &&
      !(callee is MethodElement && callee.isAbstract) &&
      usage.workspacePaths.contains(usage._path(callee));

  void _arguments(ArgumentList node) {
    if (_generated) return;
    var callee = switch (node.parent) {
      final MethodInvocation parent => parent.methodName.element,
      final InstanceCreationExpression parent => parent.constructorName.element,
      final FunctionExpressionInvocation parent => switch (parent.function) {
        final SimpleIdentifier identifier => identifier.element,
        final PrefixedIdentifier identifier => identifier.identifier.element,
        _ => null,
      },
      _ => null,
    };
    if (_hasWorkspaceBody(callee)) return;

    final candidates = <(AstNode, Expression, Set<FlutterL10n>)>[];
    for (final argument in node.arguments) {
      final expression = l10nValueExpression(argument);
      if (expression == null) continue;
      final families = {
        ...usage._types(expression.staticType),
        if (expression is AsExpression)
          ...usage._types(expression.expression.staticType),
      };
      if (families.isNotEmpty) candidates.add((argument, expression, families));
    }
    if (candidates.isEmpty) return;

    final parent = node.parent;
    if (callee is MethodElement &&
        callee.isAbstract &&
        parent is MethodInvocation) {
      callee =
          origins.concreteMethod(parent.realTarget, callee.name!) ?? callee;
    }
    if (_hasWorkspaceBody(callee)) return;
    final localCallback = parent is FunctionExpressionInvocation
        ? origins.isLocalCallback(parent.function)
        : parent is MethodInvocation &&
              (origins.isRecordCallback(parent) ||
                  parent.realTarget == null &&
                      origins.isLocalCallback(parent.methodName));
    if (localCallback) return;
    for (final (argument, expression, families) in candidates) {
      if (usage.models.accepts(callee, node, argument)) continue;
      usage._escape(families, expression, path);
    }
  }

  @override
  void visitArgumentList(ArgumentList node) {
    _arguments(node);
    super.visitArgumentList(node);
  }
}
