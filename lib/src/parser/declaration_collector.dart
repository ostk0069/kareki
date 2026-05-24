import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

import 'package:kareki/src/model/declaration.dart';

/// Result of parsing a single Dart source file.
class ParsedFile {
  ParsedFile({
    required this.path,
    required this.packageName,
    required this.declarations,
    required this.imports,
    required this.parts,
    required this.partOf,
    required this.exports,
    required this.fileLevelIgnores,
    required this.topLevelIdentifierReferences,
    required this.isGeneratedByHeader,
    required this.hasTopLevelMain,
  });

  final String path;
  final String packageName;
  final List<DeclarationRecord> declarations;

  /// `import 'uri'` URIs.
  final List<String> imports;

  /// `part 'uri'` URIs.
  final List<String> parts;

  /// The library uri this file is a part of, when applicable.
  final String? partOf;

  /// `export 'uri'` URIs.
  final List<String> exports;

  /// Simple name set silenced via `// kareki: ignore_for_file=...`.
  final Set<String> fileLevelIgnores;

  /// All top-level identifier names referenced anywhere in the file. Used
  /// for generated-code keep-alive scanning.
  final Set<String> topLevelIdentifierReferences;

  /// `true` when the file's first content lines contain a standard
  /// "GENERATED CODE - DO NOT MODIFY BY HAND" header, indicating it was
  /// produced by a codegen tool whose extension is not in the default
  /// exclude list (e.g. hand-named generated files like the
  /// `js_callback_schema/lib/models/*.dart` set).
  final bool isGeneratedByHeader;

  /// `true` when the file declares a top-level `main` function. Used to
  /// detect entry-point files (test helpers in `test/` directories that do
  /// not follow the `*_test.dart` naming convention but are still
  /// executable by `flutter test`).
  final bool hasTopLevelMain;
}

/// Parses a Dart source file and extracts declarations plus their outgoing
/// simple-name references.
class DeclarationCollector {
  ParsedFile collect({
    required String path,
    required String packageName,
    required String content,
  }) {
    final result = parseString(
      content: content,
      path: path,
      throwIfDiagnostics: false,
    );
    final unit = result.unit;
    final lineInfo = unit.lineInfo;

    final imports = <String>[];
    final parts = <String>[];
    final exports = <String>[];
    String? partOf;
    for (final directive in unit.directives) {
      if (directive is ImportDirective) {
        final uri = directive.uri.stringValue;
        if (uri != null) imports.add(uri);
        // Conditional imports: `import 'stub.dart' if (dart.library.html)
        // 'browser.dart'`. The default URI is consumed above; here we also
        // record every alternative URI so platform-specific files are not
        // reported as unused.
        for (final config in directive.configurations) {
          final altUri = config.uri.stringValue;
          if (altUri != null) imports.add(altUri);
        }
      } else if (directive is PartDirective) {
        final uri = directive.uri.stringValue;
        if (uri != null) parts.add(uri);
      } else if (directive is ExportDirective) {
        final uri = directive.uri.stringValue;
        if (uri != null) exports.add(uri);
        for (final config in directive.configurations) {
          final altUri = config.uri.stringValue;
          if (altUri != null) exports.add(altUri);
        }
      } else if (directive is PartOfDirective) {
        partOf = directive.uri?.stringValue ?? directive.libraryName?.name;
      }
    }

    final declarations = <DeclarationRecord>[];
    final topLevelReferences = <String>{};

    for (final member in unit.declarations) {
      _visitTopLevel(
        member: member,
        packageName: packageName,
        path: path,
        lineInfo: lineInfo,
        outDeclarations: declarations,
        outAllReferences: topLevelReferences,
      );
    }

    final fileLevelIgnores = _collectFileIgnores(content);
    final isGeneratedByHeader = _detectGeneratedHeader(content);
    final hasTopLevelMain = declarations.any(
      (d) =>
          d.name == 'main' &&
          d.enclosingTypeName == null &&
          d.kind == DeclarationKind.function,
    );
    return ParsedFile(
      path: path,
      packageName: packageName,
      declarations: declarations,
      imports: imports,
      parts: parts,
      partOf: partOf,
      exports: exports,
      fileLevelIgnores: fileLevelIgnores,
      topLevelIdentifierReferences: topLevelReferences,
      isGeneratedByHeader: isGeneratedByHeader,
      hasTopLevelMain: hasTopLevelMain,
    );
  }

  /// Whether [content] begins with a recognizable codegen marker.
  ///
  /// Many tools (json_serializable, freezed, openapi-generator, and many
  /// in-house generators) emit one of these headers regardless of the
  /// file extension.
  bool _detectGeneratedHeader(String content) {
    // Only inspect the very top of the file to keep this cheap.
    final head = content.length > 512 ? content.substring(0, 512) : content;
    if (head.contains('GENERATED CODE - DO NOT MODIFY BY HAND')) return true;
    if (head.contains(
      '// **************************************************'
      '*********************',
    )) {
      return true;
    }
    if (head.contains('AUTO-GENERATED FILE. DO NOT EDIT')) return true;
    return false;
  }

  void _visitTopLevel({
    required CompilationUnitMember member,
    required String packageName,
    required String path,
    required LineInfo lineInfo,
    required List<DeclarationRecord> outDeclarations,
    required Set<String> outAllReferences,
  }) {
    if (member is ClassDeclaration) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      outDeclarations.add(
        _record(
          name: name,
          kind: DeclarationKind.classDecl,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: _annotationNames(member.metadata),
        ),
      );
      for (final child in member.members) {
        _visitClassMember(
          enclosingTypeName: name,
          member: child,
          packageName: packageName,
          path: path,
          lineInfo: lineInfo,
          outDeclarations: outDeclarations,
          outAllReferences: outAllReferences,
        );
      }
    } else if (member is MixinDeclaration) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      outDeclarations.add(
        _record(
          name: name,
          kind: DeclarationKind.mixinDecl,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: _annotationNames(member.metadata),
        ),
      );
      for (final child in member.members) {
        _visitClassMember(
          enclosingTypeName: name,
          member: child,
          packageName: packageName,
          path: path,
          lineInfo: lineInfo,
          outDeclarations: outDeclarations,
          outAllReferences: outAllReferences,
        );
      }
    } else if (member is EnumDeclaration) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      outDeclarations.add(
        _record(
          name: name,
          kind: DeclarationKind.enumDecl,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: _annotationNames(member.metadata),
        ),
      );
      for (final child in member.members) {
        _visitClassMember(
          enclosingTypeName: name,
          member: child,
          packageName: packageName,
          path: path,
          lineInfo: lineInfo,
          outDeclarations: outDeclarations,
          outAllReferences: outAllReferences,
        );
      }
    } else if (member is ExtensionDeclaration) {
      final nameToken = member.name;
      final extensionName = nameToken?.lexeme;
      if (nameToken != null) {
        final visitor = _ReferenceVisitor()..visit(member);
        outAllReferences.addAll(visitor.names);
        outDeclarations.add(
          _record(
            name: nameToken.lexeme,
            kind: DeclarationKind.extensionDecl,
            token: nameToken,
            node: member,
            lineInfo: lineInfo,
            packageName: packageName,
            path: path,
            outgoingNames: visitor.names,
            annotations: _annotationNames(member.metadata),
          ),
        );
      }
      for (final child in member.members) {
        _visitClassMember(
          enclosingTypeName: extensionName,
          member: child,
          packageName: packageName,
          path: path,
          lineInfo: lineInfo,
          outDeclarations: outDeclarations,
          outAllReferences: outAllReferences,
        );
      }
    } else if (member is FunctionDeclaration) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      final isGetter = member.isGetter;
      final isSetter = member.isSetter;
      final annotations = _annotationNames(member.metadata);
      final unusedParameters = _detectUnusedParameters(
        params: member.functionExpression.parameters,
        body: member.functionExpression.body,
        initializers: null,
        annotations: annotations,
        isOperator: false,
        lineInfo: lineInfo,
      );
      outDeclarations.add(
        _record(
          name: name,
          kind: isGetter
              ? DeclarationKind.getter
              : isSetter
              ? DeclarationKind.setter
              : DeclarationKind.function,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: annotations,
          unusedParameters: unusedParameters,
        ),
      );
    } else if (member is TopLevelVariableDeclaration) {
      for (final variable in member.variables.variables) {
        final name = variable.name.lexeme;
        final visitor = _ReferenceVisitor()..visit(variable);
        outAllReferences.addAll(visitor.names);
        outDeclarations.add(
          _record(
            name: name,
            kind: DeclarationKind.topLevelVariable,
            token: variable.name,
            node: variable,
            lineInfo: lineInfo,
            packageName: packageName,
            path: path,
            outgoingNames: visitor.names,
            annotations: _annotationNames(member.metadata),
          ),
        );
      }
    } else if (member is GenericTypeAlias) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      outDeclarations.add(
        _record(
          name: name,
          kind: DeclarationKind.typedefDecl,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: _annotationNames(member.metadata),
        ),
      );
    } else if (member is FunctionTypeAlias) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      outDeclarations.add(
        _record(
          name: name,
          kind: DeclarationKind.typedefDecl,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: _annotationNames(member.metadata),
        ),
      );
    }
  }

  void _visitClassMember({
    required String? enclosingTypeName,
    required ClassMember member,
    required String packageName,
    required String path,
    required LineInfo lineInfo,
    required List<DeclarationRecord> outDeclarations,
    required Set<String> outAllReferences,
  }) {
    if (member is MethodDeclaration) {
      final name = member.name.lexeme;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      final annotations = _annotationNames(member.metadata);
      final unusedParameters = _detectUnusedParameters(
        params: member.parameters,
        body: member.body,
        initializers: null,
        annotations: annotations,
        isOperator: member.isOperator,
        lineInfo: lineInfo,
      );
      outDeclarations.add(
        _record(
          name: name,
          kind: member.isGetter
              ? DeclarationKind.getter
              : member.isSetter
              ? DeclarationKind.setter
              : DeclarationKind.method,
          token: member.name,
          node: member,
          lineInfo: lineInfo,
          packageName: packageName,
          path: path,
          outgoingNames: visitor.names,
          annotations: annotations,
          enclosingTypeName: enclosingTypeName,
          unusedParameters: unusedParameters,
        ),
      );
    } else if (member is FieldDeclaration) {
      for (final variable in member.fields.variables) {
        final name = variable.name.lexeme;
        final visitor = _ReferenceVisitor()..visit(variable);
        outAllReferences.addAll(visitor.names);
        outDeclarations.add(
          _record(
            name: name,
            kind: DeclarationKind.field,
            token: variable.name,
            node: variable,
            lineInfo: lineInfo,
            packageName: packageName,
            path: path,
            outgoingNames: visitor.names,
            annotations: _annotationNames(member.metadata),
            enclosingTypeName: enclosingTypeName,
          ),
        );
      }
    } else if (member is ConstructorDeclaration) {
      final nameToken = member.name;
      final visitor = _ReferenceVisitor()..visit(member);
      outAllReferences.addAll(visitor.names);
      final annotations = _annotationNames(member.metadata);
      final unusedParameters = _detectUnusedParameters(
        params: member.parameters,
        body: member.body,
        initializers: member.initializers,
        annotations: annotations,
        isOperator: false,
        lineInfo: lineInfo,
      );
      // Named constructors are addressable. Unnamed constructors share the
      // class's reachability (their visibility comes for free).
      if (nameToken != null) {
        outDeclarations.add(
          _record(
            name: nameToken.lexeme,
            kind: DeclarationKind.constructor,
            token: nameToken,
            node: member,
            lineInfo: lineInfo,
            packageName: packageName,
            path: path,
            outgoingNames: visitor.names,
            annotations: annotations,
            enclosingTypeName: enclosingTypeName,
            unusedParameters: unusedParameters,
          ),
        );
      }
    }
  }

  DeclarationRecord _record({
    required String name,
    required DeclarationKind kind,
    required Token token,
    required AstNode node,
    required LineInfo lineInfo,
    required String packageName,
    required String path,
    required Set<String> outgoingNames,
    required Set<String> annotations,
    String? enclosingTypeName,
    List<ParameterRecord> unusedParameters = const [],
  }) {
    final location = lineInfo.getLocation(token.offset);
    return DeclarationRecord(
      name: name,
      kind: kind,
      packageName: packageName,
      libraryPath: path,
      offset: token.offset,
      length: token.length,
      line: location.lineNumber,
      column: location.columnNumber,
      isPublic: !name.startsWith('_'),
      outgoingNames: outgoingNames,
      annotations: annotations,
      enclosingTypeName: enclosingTypeName,
      unusedParameters: unusedParameters,
    );
  }

  /// Returns parameters declared by [params] that are never referenced
  /// inside [body] or [initializers]. Returns an empty list when the
  /// callable is intentionally excluded from the analysis: overrides,
  /// operators, abstract / external / native callables with no
  /// implementation to inspect.
  ///
  /// Identifier matching is name-based (no element resolution), so a
  /// parameter shadowed by an unrelated field of the same name will be
  /// considered referenced. Same approximation as the rest of kareki's
  /// reachability graph.
  List<ParameterRecord> _detectUnusedParameters({
    required FormalParameterList? params,
    required FunctionBody? body,
    required NodeList<ConstructorInitializer>? initializers,
    required Set<String> annotations,
    required bool isOperator,
    required LineInfo lineInfo,
  }) {
    if (params == null) return const [];
    if (params.parameters.isEmpty) return const [];
    if (isOperator) return const [];
    if (annotations.contains('override')) return const [];

    final hasBody = body is BlockFunctionBody || body is ExpressionFunctionBody;
    final hasInitializers = initializers != null && initializers.isNotEmpty;
    // No implementation to inspect: abstract, external, native, or a
    // redirecting factory. Flagging parameters here would be noise — the
    // signature is dictated by the contract, not by the (absent) body.
    if (!hasBody && !hasInitializers) return const [];
    // Base / stub methods whose only behaviour is `throw
    // UnimplementedError(...)` are contractual: their signature is
    // dictated by the overriding subclasses (e.g. federated plugin
    // `PlatformInterface` base methods, or hand-written abstract stand-ins
    // that need a body to be testable). Flagging their parameters is
    // always a false positive.
    if (body != null && _isUnimplementedErrorStub(body)) return const [];

    final referenced = <String>{};
    if (hasBody) {
      final visitor = _ReferenceVisitor()..visit(body!);
      referenced.addAll(visitor.names);
    }
    if (hasInitializers) {
      for (final init in initializers) {
        final visitor = _ReferenceVisitor()..visit(init);
        referenced.addAll(visitor.names);
      }
    }

    return _emitUnusedParameters(params, referenced, lineInfo);
  }

  /// Whether [body] consists solely of `throw UnimplementedError(...)`,
  /// in either expression-body (`=> throw UnimplementedError()`) or
  /// single-statement block-body (`{ throw UnimplementedError(); }`)
  /// form. Matches the canonical Dart stub idiom used by
  /// `PlatformInterface` and similar "must-override" base classes.
  bool _isUnimplementedErrorStub(FunctionBody body) {
    Expression? throwExpr;
    if (body is ExpressionFunctionBody) {
      throwExpr = body.expression;
    } else if (body is BlockFunctionBody) {
      final statements = body.block.statements;
      if (statements.length != 1) return false;
      final only = statements.first;
      if (only is! ExpressionStatement) return false;
      throwExpr = only.expression;
    } else {
      return false;
    }
    if (throwExpr is! ThrowExpression) return false;
    final thrown = throwExpr.expression;
    // `parseString` runs without element resolution, so a bare
    // `UnimplementedError(...)` call (no `new` / `const` keyword) is
    // emitted as a MethodInvocation rather than an
    // InstanceCreationExpression. Match both shapes.
    if (thrown is InstanceCreationExpression) {
      return thrown.constructorName.type.name.lexeme == 'UnimplementedError';
    }
    if (thrown is MethodInvocation && thrown.target == null) {
      return thrown.methodName.name == 'UnimplementedError';
    }
    return false;
  }

  List<ParameterRecord> _emitUnusedParameters(
    FormalParameterList params,
    Set<String> referenced,
    LineInfo lineInfo,
  ) {
    final unused = <ParameterRecord>[];
    for (final param in params.parameters) {
      final inner = param is DefaultFormalParameter ? param.parameter : param;
      // `this.x` auto-assigns to a field; `super.x` auto-forwards to the
      // super constructor. Neither needs a body reference.
      if (inner is FieldFormalParameter) continue;
      if (inner is SuperFormalParameter) continue;
      final nameToken = inner.name;
      if (nameToken == null) continue;
      final name = nameToken.lexeme;
      if (name.isEmpty) continue;
      // The Dart-wide convention `_`, `__`, ... marks a parameter as
      // intentionally unused (typically required by a callback signature).
      if (RegExp(r'^_+$').hasMatch(name)) continue;
      if (referenced.contains(name)) continue;
      final location = lineInfo.getLocation(nameToken.offset);
      unused.add(
        ParameterRecord(
          name: name,
          line: location.lineNumber,
          column: location.columnNumber,
          length: nameToken.length,
          offset: nameToken.offset,
        ),
      );
    }
    return unused;
  }

  Set<String> _annotationNames(NodeList<Annotation> metadata) {
    final names = <String>{};
    for (final annotation in metadata) {
      final name = annotation.name;
      if (name is SimpleIdentifier) {
        names.add(name.name);
      } else if (name is PrefixedIdentifier) {
        names.add(name.identifier.name);
      }
      final constructor = annotation.constructorName;
      if (constructor != null) names.add(constructor.name);
    }
    return names;
  }

  Set<String> _collectFileIgnores(String content) {
    final names = <String>{};
    // Capture stays within the comment line: `[\w, \t]+` deliberately
    // excludes newlines so the match does not swallow blank lines and the
    // following import statement (which would corrupt the captured rule
    // names — comma-split would then yield a single token like
    // `test_only_used\n\nimport 'package`).
    final pattern = RegExp(r'//\s*kareki:\s*ignore_for_file\s*=\s*([\w, \t]+)');
    for (final match in pattern.allMatches(content)) {
      final values = match.group(1) ?? '';
      for (final raw in values.split(',')) {
        final trimmed = raw.trim();
        if (trimmed.isNotEmpty) names.add(trimmed);
      }
    }
    return names;
  }
}

/// Walks an AST subtree collecting simple identifier names referenced
/// anywhere within. Used as outgoing edges for the reachability graph.
class _ReferenceVisitor extends RecursiveAstVisitor<void> {
  final Set<String> names = {};

  void visit(AstNode node) => node.accept(this);

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    names.add(node.name);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    names.add(node.identifier.name);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    names.add(node.name.lexeme);
    super.visitNamedType(node);
  }
}
