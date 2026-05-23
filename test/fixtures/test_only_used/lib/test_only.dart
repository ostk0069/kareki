// Declared in production source (lib/) but referenced only from a
// test file under test/. Expected to be flagged as `test_only_used`.
String testOnlyFn() => 'only used by test/test_only_test.dart';

class TestOnlyClass {
  String greet() => 'test only';
}
