import 'package:unused_parameter_sample/sample.dart';

void main() {
  compute(1, 2);
  greet('world', title: 'hi');
  onTapHandler(1, 2);
  final svc = ChildService();
  svc.doWork(1, 2);
  // Touch the operator and constructors so the enclosing declarations
  // are reachable.
  // ignore: unrelated_type_equality_checks
  Service() > 1;
  Box.dims(1, 2);
  Box.tagged(1, 'x');

  // Reference GestureExclusion as a type so it's reachable.
  GestureExclusion? stub;
  print(stub);
}
