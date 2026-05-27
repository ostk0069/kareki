/// `host` is passed by bin/main.dart; `port` never is — kareki flags
/// `port` as `unused_parameter_optional`.
String buildUrl({String host = 'localhost', int port = 8080}) {
  return '$host:$port';
}

class Service {
  /// `a` is read in the body; `unusedTwo` is not — kareki flags
  /// `unusedTwo` as `unused_parameter`.
  void doWork(int a, int unusedTwo) {
    print(a);
  }
}
