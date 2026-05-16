/// A named set of annotation rules that kareki uses to suppress false
/// positives for a particular framework, codegen tool, or in-house
/// generator.
///
/// Presets bundle together two related but distinct concepts:
///
/// 1. **Keep-alive annotations**: when one of [keepAliveAnnotations] is
///    attached to a declaration, that declaration is treated as
///    reachable by the BFS even if no caller is found. Used because
///    framework-managed code is invoked via reflection, code generation,
///    or runtime dispatch that the simple-name BFS cannot follow.
///
/// 2. **Annotation-implied pub packages**: when one of the keys in
///    [annotationImpliedPackages] appears anywhere in source, the
///    listed pub packages are treated as "needed" for
///    `unused_pub_dependency` reporting — even if no source file
///    imports them directly (typically because the import lives in a
///    generated `.g.dart` / `.freezed.dart` file that kareki excludes
///    from analysis).
class Preset {
  const Preset({
    required this.name,
    this.keepAliveAnnotations = const {},
    this.annotationImpliedPackages = const {},
  });

  /// Stable identifier used to opt-in/out and to override built-ins.
  ///
  /// User configuration that defines a `custom_presets` entry with the
  /// same [name] replaces the built-in preset entirely.
  final String name;

  /// Annotation simple names that mark a declaration as keep-alive.
  final Set<String> keepAliveAnnotations;

  /// Annotation simple name → pub packages that the annotation
  /// implicitly requires in `pubspec.yaml`.
  final Map<String, Set<String>> annotationImpliedPackages;
}
