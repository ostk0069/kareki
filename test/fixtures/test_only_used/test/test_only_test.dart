import 'package:sample_test_only/test_only.dart';

void main() {
  // Pretend this is a test that exercises testOnlyFn / TestOnlyClass.
  // No production code references either symbol.
  final a = testOnlyFn();
  final b = TestOnlyClass().greet();
  assert(a.isNotEmpty);
  assert(b.isNotEmpty);
}
