/// One issue reported by `kareki doctor`.
class DoctorFinding {
  DoctorFinding({required this.kind, required this.subject, this.detail});

  /// Issue category — see [DoctorIssueKind] for the canonical ids.
  final String kind;

  /// Primary subject of the finding (e.g. the dead glob string, the
  /// ignored package name, or the file path of an ineffective ignore).
  final String subject;

  /// Optional human-readable disambiguator (e.g. the source config key
  /// for ignore.dependencies, or the rule id of the dead directive).
  final String? detail;
}

/// Stable issue ids used by both reporters and tests.
abstract final class DoctorIssueKind {
  /// `exclude.files` glob that matches no `.dart` file in the workspace.
  static const String unusedExclude = 'unused-exclude';

  /// `ignore.packages` entry whose package is absent from the workspace.
  static const String unusedIgnorePackage = 'unused-ignore-package';

  /// `ignore.dependencies` map keyed on a package that is absent from
  /// the workspace.
  static const String unusedIgnoreDependenciesPackage =
      'unused-ignore-dependencies-package';

  /// `ignore.dependencies.<pkg>` entry whose dep is not declared in the
  /// package's pubspec.
  static const String unusedIgnoreDependency = 'unused-ignore-dependency';

  /// `// kareki: ignore_for_file=<rule>` with no matching finding from
  /// the corresponding rule.
  static const String unusedIgnoreDirective = 'unused-ignore-directive';
}
