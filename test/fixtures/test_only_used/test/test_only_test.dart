import 'package:sample_test_only/scroll_physics_like.dart';
import 'package:sample_test_only/test_only.dart';

void main() {
  // Pretend this is a test that exercises testOnlyFn / TestOnlyClass.
  // No production code references either symbol.
  final a = testOnlyFn();
  final b = TestOnlyClass().greet();
  assert(a.isNotEmpty);
  assert(b.isNotEmpty);

  // Calls the override method by name. Production code only uses the
  // base interface — kareki should NOT flag ProductionHandler.applyTo
  // as test_only_used because of the @override exemption.
  ProductionHandler().applyTo();
}
