import 'package:meta/meta.dart';

/// Reachable from bin/main.dart — must NOT be flagged.
@immutable
class Greeting {
  const Greeting(this.name);
  final String name;
}

String greet(String name) => 'hello, ${Greeting(name).name}';

/// Only active is referenced; inactive demonstrates unused enum values.
enum Status { active, inactive }
