/// kareki — multi-package dead-code detector for Dart and Flutter
/// monorepos.
///
/// Most users invoke kareki through its CLI (`dart run kareki`). This
/// library exposes the same building blocks for embedding in custom
/// tooling.
///
/// ## Quick start
///
/// ```dart
/// import 'package:kareki/kareki.dart';
///
/// void main() {
///   const root = '.';
///   final config = KarekiConfig.load(root);
///   final result = KarekiRunner().run(
///     RunRequest(rootPath: root, config: config),
///   );
///   stdout.writeln(
///     TextReporter().render(result.findings, rootPath: root),
///   );
/// }
/// ```
///
/// ## Entry points
///
/// | Type | Purpose |
/// |---|---|
/// | [KarekiRunner] | Orchestrates parsing, reachability analysis, and rule evaluation. |
/// | [RunRequest] / [RunResult] | Input / output of a single run. |
/// | [KarekiConfig] | Project configuration; load via [KarekiConfig.load] or build via [KarekiConfig.defaults]. |
/// | [Finding] / [RuleId] / [Severity] | Detection records and rule identifiers. |
/// | [Reporter] / [TextReporter] / [JsonReporter] | Format findings for output. |
/// | [DeclarationCollector] / [ParsedFile] / [DeclarationRecord] | Low-level parsing primitives, exposed for custom tooling. |
/// | [PackageInfo] | Metadata for a discovered pub package. |
library;

export 'src/config/kareki_config.dart';
export 'src/model/declaration.dart';
export 'src/model/finding.dart';
export 'src/model/package_info.dart';
export 'src/parser/declaration_collector.dart';
export 'src/reporter/reporter.dart';
export 'src/runner.dart';
