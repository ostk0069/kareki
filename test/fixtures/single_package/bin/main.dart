import 'package:sample/used.dart';

void main() {
  final value = addOne(2);
  final t = UsedThing();
  // ignore: avoid_print
  print('$value ${t.greet()}');
}
