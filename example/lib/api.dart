import 'package:meta/meta.dart';

/// Reachable from bin/main.dart — must NOT be flagged.
@immutable
class Greeting {
  const Greeting(this.name);
  final String name;
}

String greet(String name) => 'hello, ${Greeting(name).name}';

/// Public, declared in an imported file, but nobody references it —
/// kareki flags it as `unused_element`.
class UnusedPublicApi {}
