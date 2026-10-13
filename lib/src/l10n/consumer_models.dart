import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:kareki/src/l10n/ast_values.dart';
import 'package:kareki/src/reachability/external_decoder_models.dart';

/// Audited value-registration and null-matcher contracts. Source closure changes
/// disable each model; a package name or version alone never grants trust.
class L10nConsumerModels {
  L10nConsumerModels(this.isWorkspaceSource);

  final bool Function(String) isWorkspaceSource;
  final _verified = <LibraryElement, bool>{};

  static const _contracts = {
    'package:mockito/src/mock.dart': {
      // Mockito 5.6.4: when discards its value; thenReturn stores a response;
      // Mock.noSuchMethod's named defaults are returned without key access.
      '9a47cbb00eaa315b927ac09f4c1268acd6e42f88097ef69fd5bee419ef97ac11',
      '340bc30da2fa3fdb31b94c68e53b3dbc4094595efb0626955ca44d895deaca7c',
    },
    'package:matcher/src/expect/expect.dart': {
      // matcher 0.12.19: only the exact null matchers below are modeled.
      'd783dea3e01089d291225d4f324014ff2e47f9018e1661dfa788dfca8b79c61b',
      'd64fab8d94566ca1cfd44d5fac2ccf71c71b3ce88926e68c85342e008e6ae796',
    },
    // Flutter 3.41.4 forwards expect's values after an argument-free guardSync.
    'package:flutter_test/src/widget_tester.dart': {
      '29adb9b70856b44fec9adef7eeb3f780c775c01a0e07276f95261e2902dd07c4',
    },
    'package:matcher/src/core_matchers.dart': {
      '72e4209fa67629edbaf4f7115d7a69fe8bfbc4ab3f914b48834919f8d068076b',
      '8ae23e43dc31ee28577c2c116bc881fc33e2eec83960145ba8c5b5b7611fe447',
    },
  };

  bool _trusted(Element? element, String uri) {
    final library = element?.library;
    if (library == null || library.uri.toString() != uri) return false;
    return _verified.putIfAbsent(library, () {
      try {
        final snapshot = decoderSourceSnapshot(library);
        return _contracts[uri]!.contains(snapshot.digest) &&
            !snapshot.libraries.any(
              (library) => library.fragments.any(
                (fragment) => isWorkspaceSource(fragment.source.fullName),
              ),
            );
      } on Object {
        return false;
      }
    });
  }

  /// This approval applies to one argument, never the entire invocation.
  bool accepts(Element? callee, ArgumentList arguments, AstNode argument) {
    const mock = 'package:mockito/src/mock.dart';
    if (_trusted(callee, mock)) {
      if (callee is GetterElement && callee.name == 'when') {
        return arguments.arguments.first == argument;
      }
      if (callee is MethodElement) {
        final host = callee.enclosingElement?.name;
        if (host == 'PostExpectation' && callee.name == 'thenReturn') {
          return arguments.arguments.first == argument;
        }
        if (host == 'Mock' &&
            callee.name == 'noSuchMethod' &&
            l10nValueName(argument) != null) {
          return {
            'returnValue',
            'returnValueForMissingStub',
          }.contains(l10nValueName(argument));
        }
      }
    }
    if (callee is TopLevelFunctionElement &&
        callee.name == 'expect' &&
        arguments.arguments.first == argument &&
        arguments.arguments.length >= 2 &&
        !arguments.arguments.any(
          (argument) => l10nValueName(argument) == 'formatter',
        ) &&
        (_trusted(callee, 'package:matcher/src/expect/expect.dart') ||
            _trusted(callee, 'package:flutter_test/src/widget_tester.dart'))) {
      final matcher = l10nValueExpression(arguments.arguments[1]);
      final element = switch (matcher) {
        SimpleIdentifier() => matcher.element,
        PrefixedIdentifier() => matcher.identifier.element,
        _ => null,
      };
      return element is GetterElement &&
          {'isNull', 'isNotNull'}.contains(element.name) &&
          _trusted(element, 'package:matcher/src/core_matchers.dart');
    }
    return false;
  }
}
