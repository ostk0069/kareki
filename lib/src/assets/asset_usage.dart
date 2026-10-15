import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:kareki/src/assets/flutter_assets.dart';
import 'package:kareki/src/l10n/ast_values.dart';
import 'package:path/path.dart' as p;

/// Records generated member dependencies separately from user references.
/// Only strings/ids survive resolution; analyzer elements and ASTs do not.
class AssetUsage {
  AssetUsage(this.assets, this.isWorkspaceSource, this.canonical);

  final List<FlutterAsset> assets;
  final bool Function(String) isWorkspaceSource;
  final String Function(String) canonical;
  late final bool _hasFonts = assets.any((asset) => asset.font);
  final used = <String>{};
  final warnings = <String>{};
  final _references = <String>{};
  final _edges = <String, Set<String>>{};
  final _resources = <String, Set<String>>{};
  final _members = <String, Set<String>>{};
  final _containers = <String, Set<String>>{};
  final _escapedTypes = <String>{};
  final _generatedSources = <String, bool>{};
  final _consumerLibraries = <LibraryElement, bool>{};
  final _validatedColors = <String>{};

  late final List<FlutterAsset> _colors = assets
      .where((a) => a.color != null)
      .toList();
  late final Set<String> _colorOutputs = {
    for (final asset in _colors) canonical(asset.color!.outputPath),
  };

  bool isColorOutput(String path) => _colorOutputs.contains(canonical(path));

  void _colorClass(ClassElement type) {
    if (_colors.isEmpty) return;
    final source = type.firstFragment.libraryFragment.source.fullName;
    final colors = _colors
        .where(
          (a) =>
              canonical(a.color!.outputPath) == canonical(source) &&
              a.color!.className == type.name,
        )
        .toList();
    if (colors.isEmpty) return;
    final expected = {for (final asset in colors) ...asset.color!.members};
    final fields = {
      for (final field in type.fields)
        if (field.isStatic && field.isConst) field.name: field,
    };
    if (!fields.keys.toSet().containsAll(expected) ||
        fields.length != expected.length) {
      throw FormatException(
        '$source: Color API does not match XML inputs. Run FlutterGen.',
      );
    }
    for (final asset in colors) {
      _validatedColors.add(asset.id);
      for (final member in asset.color!.members) {
        _resources.putIfAbsent(_id(fields[member])!, () => {}).add(asset.id);
      }
    }
  }

  late final Set<String> _resourceRoots = {
    for (final asset in assets) canonical(p.dirname(asset.pubspecPath)),
  };
  static final _densityDirectory = RegExp(r'/\d+(?:\.\d+)?x/');

  bool _generatedElement(Element? element) {
    final source =
        element?.nonSynthetic.baseElement.firstFragment.libraryFragment?.source;
    if (source == null) return false;
    return _generatedSources.putIfAbsent(source.fullName, () {
      if (!_resourceRoots.any(
        (root) => p.isWithin(root, canonical(source.fullName)),
      )) {
        return false;
      }
      final contents = source.contents.data;
      if (isColorOutput(source.fullName)) return true;
      final header = contents.substring(0, contents.length.clamp(0, 1000));
      return header.contains('GENERATED CODE') &&
          (header.contains('FlutterGen') ||
              {
                'assets.gen.dart',
                'fonts.gen.dart',
              }.contains(p.basename(source.fullName)));
    });
  }

  void _manifest(String value, String site) {
    final fonts = value == 'FontManifest.json';
    if (!fonts &&
        !{'AssetManifest.json', 'AssetManifest.bin'}.contains(value)) {
      return;
    }
    final candidates = assets
        .where((asset) => asset.color == null && asset.font == fonts)
        .map((asset) => asset.id)
        .toSet();
    if (candidates.isEmpty) return;
    used.addAll(candidates);
    warnings.add(
      '${fonts ? 'Font' : 'Asset'} manifest consumer at $site; bundled ${fonts ? 'font families' : 'assets'} retained conservatively.',
    );
  }

  void _externalConsumer(Element? element, String site) {
    final library = element?.library;
    if (!_hasFonts ||
        library == null ||
        library.isInSdk ||
        !library.uri.isScheme('package') ||
        library.uri.pathSegments.first == 'flutter' ||
        library.uri.pathSegments.first == 'flutter_test' ||
        library.fragments.any(
          (fragment) => isWorkspaceSource(fragment.source.fullName),
        )) {
      return;
    }
    // External bodies are opaque consumers. An actual manifest literal in the
    // selected library's same-package import/part closure establishes a reason
    // to retain candidate fonts, not proof that each family is rendered.
    if (_consumerLibraries.putIfAbsent(library, () {
      final pending = [library];
      final seen = <LibraryElement>{};
      final package = library.uri.pathSegments.first;
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (!seen.add(current)) continue;
        final known = current == library ? null : _consumerLibraries[current];
        if (known == true) return true;
        if (known == false) continue;
        for (final fragment in current.fragments) {
          final source = fragment.source;
          final text = source.contents.data;
          if (text.contains('FontManifest.json')) {
            final manifest = _ManifestLiteralVisitor();
            parseString(
              content: text,
              path: source.fullName,
            ).unit.accept(manifest);
            if (manifest.fonts) return true;
          }
          pending.addAll(
            [...fragment.importedLibraries, ...current.exportedLibraries].where(
              (dependency) =>
                  dependency.uri.isScheme('package') &&
                  dependency.uri.pathSegments.first == package,
            ),
          );
        }
      }
      return false;
    })) {
      _manifest('FontManifest.json', site);
    }
  }

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
      if (asset.color != null) continue;
      for (final path in {asset.name, ...asset.fontFiles}) {
        for (final key in [
          '${asset.packageName}|$path',
          'packages/${asset.packageName}/$path',
        ]) {
          result.putIfAbsent(key, () => {}).add(asset.id);
        }
      }
    }
    return result;
  }

  Set<String> _matches(String value, String packageName) {
    // Directly requested density variants also retain the logical image.
    final logical = value.replaceAll(_densityDirectory, '/');
    return {
      for (final path in {value, logical}) ...{
        ...?_paths['$packageName|$path'],
        ...?_paths[path],
        if (packageName == '*')
          for (final asset in assets)
            if (asset.color == null &&
                (asset.name == path || asset.fontFiles.contains(path)))
              asset.id,
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
    for (final asset in assets) {
      if (asset.color != null && !_validatedColors.contains(asset.id)) {
        throw FormatException(
          '${asset.color!.outputPath}: Generated color class ${asset.color!.className} was not resolved. Run FlutterGen.',
        );
      }
    }
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
    for (final font in assets.where(
      (asset) => asset.font && used.contains(asset.id),
    )) {
      for (final file in font.fontFiles) {
        used.addAll(_matches(file, font.packageName));
      }
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

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) usage._colorClass(element);
    super.visitClassDeclaration(node);
  }

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
      if (ownerPackage == '*' && matches.isNotEmpty) {
        usage.warnings.add(
          'Unknown asset package at $path; matching resources retained conservatively.',
        );
      }
      usage._manifest(value, path);
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
    if (element is VariableElement &&
        element.isConst &&
        element.type.isDartCoreString) {
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
    final id = usage._generatedElement(node.element)
        ? usage._id(node.element)
        : null;
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
    if (variable is VariableElement &&
        variable.isConst &&
        variable.type.isDartCoreString) {
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
      if (generated) {
        final id = usage._id(node.element);
        if (_owner != null && id != null) {
          usage._edges.putIfAbsent(_owner!, () => {}).add(id);
        }
      } else {
        final generatedMember = usage._generatedElement(node.element);
        if (generatedMember) {
          final id = usage._id(node.element);
          if (id != null) usage._references.add(id);
        }
        final value = generatedMember ? null : _value(node);
        if (value != null) _record(value, ownerPackage: _argumentPackage(node));
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
        _record(buffer.toString(), ownerPackage: _argumentPackage(node));
      } else if (buffer.isNotEmpty) {
        final prefix = buffer.toString();
        final retained = {
          for (final asset in usage.assets)
            if (!asset.font &&
                asset.color == null &&
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
    final staticType = expression.staticType;
    if (staticType is! InterfaceType ||
        !usage._generatedElement(staticType.element)) {
      return;
    }
    final type = usage._classId(staticType);
    if (type != null) usage._escapedTypes.add(type);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!generated) {
      usage._externalConsumer(node.methodName.element, '$path:${node.offset}');
      final element = node.methodName.element;
      if (element?.enclosingElement?.name == 'AssetManifest' &&
          element?.library?.uri.toString() ==
              'package:flutter/src/services/asset_manifest.dart' &&
          node.methodName.name == 'loadFromAssetBundle') {
        usage._manifest('AssetManifest.bin', '$path:${node.offset}');
      }
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!generated) {
      usage._externalConsumer(
        node.constructorName.element,
        '$path:${node.offset}',
      );
    }
    super.visitInstanceCreationExpression(node);
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

class _ManifestLiteralVisitor extends RecursiveAstVisitor<void> {
  bool fonts = false;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.stringValue == 'FontManifest.json') fonts = true;
    super.visitSimpleStringLiteral(node);
  }
}
