import 'package:kareki_example/test_only.dart';

void main() {
  final value = testOnlyHelper();
  assert(value.isNotEmpty);
}
