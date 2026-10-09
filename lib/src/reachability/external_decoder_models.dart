import 'dart:convert';

import 'package:analyzer/dart/element/element.dart';
import 'package:crypto/crypto.dart';

enum DecodedValueKind { json, yaml }

/// Reviewed return-value contracts, enabled only for exact source closures.
///
/// This is a trusted model, not automatic proof of an arbitrary decoder body.
/// Source changes (including transitive dependencies and language versions)
/// disable it. Cache scope is one analysis; never persist approval by URI/name.
class ExternalDecoderModels {
  ExternalDecoderModels({required this.isWorkspaceSource});

  final bool Function(String path) isWorkspaceSource;
  final _verified = <LibraryElement, bool>{};
  final _yamlLibraries = <LibraryElement>{};

  static const _contracts = {
    // Models apply only to external dependencies, never scanned workspace code.
    // Approval covers the non-SDK import/export/part closure, source contents,
    // and effective language versions; names or versions alone are insufficient.
    // Before registering a fingerprint:
    // 1. Review the decoder and its transitive implementation. Confirm decoded
    //    values cannot dispatch to arbitrary workspace operators.
    // 2. Inspect the closure with:
    //    dart tool/resolved_analysis/decoder_model_snapshot.dart SOURCE_FILE LIBRARY_URI
    //    Generating a digest is not approval to trust it.
    // 3. Extend test/runner/resolved_decoders_test.dart with supported cases and
    //    counterexamples: changed sources, relocation, same-name impostors,
    //    mutation, escape, and vendored implementations. Register only after
    //    review and tests pass. Unrecognized sources retain conservative analysis.
    'package:jsonc/src/json.dart': {
      '490dbda2ab9504c89d54f7c7709c283eec8025454f8b7e130985f34d043213cf',
    },
    'package:yaml/yaml.dart': {
      // yaml 3.1.3 and 3.1.4 with the reviewed dependency closure.
      'ed943841b74e59463ad8034a1263f4c80e9cdf993e54978ebff13e3b6847f57c',
      '2584cc5a3c54df15cb0fabae62081da1e8568d453d40ea1dfec466c70c3a1e1b',
    },
  };

  DecodedValueKind? kindOf(Element? element) {
    final library = element?.library;
    if (library == null) return null;
    final uri = library.uri.toString();
    final kind = switch (uri) {
      'package:jsonc/src/json.dart'
          when element is TopLevelFunctionElement &&
                  element.name == 'jsoncDecode' ||
              element is MethodElement &&
                  element.name == 'decode' &&
                  element.enclosingElement?.name == 'JsoncCodec' =>
        DecodedValueKind.json,
      'package:yaml/yaml.dart'
          when element is TopLevelFunctionElement &&
              element.name == 'loadYaml' =>
        DecodedValueKind.yaml,
      _ => null,
    };
    if (kind == null) return null;
    final verified = _verified.putIfAbsent(library, () {
      try {
        final snapshot = decoderSourceSnapshot(library);
        if (!_contracts[uri]!.contains(snapshot.digest)) return false;
        // A vendored decoder inside the scanned workspace has real [] bodies
        // of its own. This model only excludes *external* decoder targets.
        if (snapshot.libraries.any(
          (library) => library.fragments.any(
            (fragment) => isWorkspaceSource(fragment.source.fullName),
          ),
        )) {
          return false;
        }
        if (kind == DecodedValueKind.yaml) {
          _yamlLibraries.addAll(snapshot.libraries);
        }
        return true;
      } on Object {
        // Unreadable/missing/ambiguous sources cannot justify removing edges.
        return false;
      }
    });
    return verified ? kind : null;
  }

  bool isYamlNodeElement(Element? element) =>
      element?.library?.uri.toString() == 'package:yaml/src/yaml_node.dart' &&
      _yamlLibraries.contains(element?.library);
}

/// Read-only inventory for auditing/regenerating a model after human review.
/// It intentionally never adds a fingerprint to the trusted model catalog.
({String digest, Set<LibraryElement> libraries}) decoderSourceSnapshot(
  LibraryElement root,
) {
  final libraries = <LibraryElement>{};
  final pending = [root];
  final sources = <String, List<String>>{};
  while (pending.isNotEmpty) {
    final library = pending.removeLast();
    if (library.isInSdk || !libraries.add(library)) continue;
    if (library.isOriginNotExistingFile) throw StateError('Missing library');
    pending.addAll(library.exportedLibraries);
    for (final fragment in library.fragments) {
      if (fragment.isOriginNotExistingFile) throw StateError('Missing part');
      pending.addAll(fragment.importedLibraries);
      final source = fragment.source;
      final key = '${library.uri}|${source.uri}';
      if (sources.containsKey(key)) throw StateError('Ambiguous source URI');
      sources[key] = [
        key,
        library.languageVersion.effective.toString(),
        sha256.convert(utf8.encode(source.contents.data)).toString(),
      ];
    }
  }
  final keys = sources.keys.toList()..sort();
  return (
    digest: sha256
        .convert(
          utf8.encode(jsonEncode([for (final key in keys) sources[key]])),
        )
        .toString(),
    libraries: libraries,
  );
}
