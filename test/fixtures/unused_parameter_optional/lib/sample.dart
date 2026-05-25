// Top-level function with two optional named params. Only `host` is
// referenced anywhere in the workspace — `port` must be flagged.
String buildUrl({String host = 'localhost', int port = 8080}) {
  return '$host:$port';
}

// Optional positional. `extra` (index 1) is never passed by any caller.
String formatNumber(int value, [int? extra]) {
  return '$value-${extra ?? 0}';
}

class HttpClient {
  // Optional named: `timeout` is passed, `retryCount` is not.
  void send(String url, {int timeout = 1000, int retryCount = 0}) {
    print('$url $timeout $retryCount');
  }

  // Unnamed constructor with an optional named param that nobody passes.
  HttpClient({String? endpoint}) : _endpoint = endpoint;

  final String? _endpoint;
}

class Service {
  // Named constructor with two optional named params; one passed, one not.
  Service.create({String? tag, String? unusedTag})
    : _tag = tag,
      _unusedTag = unusedTag;

  final String? _tag;
  final String? _unusedTag;
}

abstract class Base {
  // Abstract: no body — must not be flagged.
  void apply({int? unusedAbstractParam});
}

class Concrete extends Base {
  // @override: signature is contractual — must not be flagged even
  // when nobody passes the parameter.
  @override
  void apply({int? unusedAbstractParam}) {
    print('applied');
  }
}

// `_` placeholder convention: must not be flagged. Modern Dart
// disallows named `_`, so we exercise the positional-optional form.
void onCallback([int? _]) {
  print('cb');
}

// `this.x` / `super.x` are skipped.
class Box {
  Box({this.width = 10, this.height = 10});
  final int width;
  final int height;
}

// PlatformInterface-style stub: signature dictated by overriders.
abstract class Platform {
  Future<void> open({String? url}) {
    throw UnimplementedError('open has not been implemented.');
  }
}
