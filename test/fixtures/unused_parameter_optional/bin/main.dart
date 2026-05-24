import 'package:unused_parameter_optional_sample/sample.dart';

void main() {
  // buildUrl: only `host` is passed; `port` should be flagged.
  buildUrl(host: 'example.com');

  // formatNumber: only the required positional is passed; the optional
  // positional `extra` (index 1) should be flagged.
  formatNumber(1);

  // HttpClient.send: only `timeout` is passed; `retryCount` flagged.
  HttpClient().send('http://x', timeout: 500);

  // Unnamed HttpClient(): `endpoint` is never passed at any call site
  // — should be flagged.

  // Service.create: only `tag` is passed; `unusedTag` flagged.
  Service.create(tag: 'a');

  // Concrete overrides Base.apply — overrides are exempt.
  Concrete().apply();

  // onCallback uses the `_` placeholder — exempt.
  onCallback();

  // Box uses `this.x` / `this.y` — exempt.
  Box();

  // Platform.open is a stub idiom — exempt.
  // (No call site needed; the rule must not fire either way.)
}
