import 'package:sample_test_only/scroll_physics_like.dart';
import 'package:sample_test_only/used_in_production.dart';

void main() {
  // ignore: avoid_print
  print(productionFn());
  // Instantiating ProductionHandler makes the class production-reachable.
  // The framework would call applyTo() via virtual dispatch, so no
  // production code references the method name directly — only the
  // test below does.
  final BaseHandler handler = ProductionHandler();
  // Pass it where something would consume it; we never call applyTo().
  // ignore: avoid_print
  print(handler.runtimeType);
}
