/// Reference evidence for one template ARB, before report suppressions.
/// Unknown keys have neither a confirmed use nor a safe unused verdict.
class LocalizationUsage {
  const LocalizationUsage({
    required this.packageName,
    required this.templatePath,
    required this.used,
    required this.unused,
    required this.unknown,
  });

  final String packageName;
  final String templatePath;
  final int used;
  final int unused;
  final int unknown;
}
