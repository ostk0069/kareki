import 'package:kareki_example/api.dart';
import 'package:kareki_example/parameters.dart';

void main() {
  greet('world');

  // `port` is never passed at any call site in the workspace —
  // kareki flags it as `unused_parameter_optional`.
  buildUrl(host: 'example.com');

  // `unusedTwo` in the body of doWork is never referenced —
  // kareki flags it as `unused_parameter`.
  Service().doWork(1, 2);
}
