// A function with one used and one unused parameter.
int compute(int used, int unusedOne) {
  return used + 1;
}

// All parameters referenced — no findings.
String greet(String name, {required String title}) {
  return title + ' ' + name;
}

// Underscore convention: must not be flagged.
void onTapHandler(int _, int __) {
  // Body intentionally ignores both parameters.
}

abstract class Repo {
  // No body — must not be flagged.
  void save(String key, int value);
}

class Service {
  // Method with an unused param.
  void doWork(int a, int unusedTwo) {
    print(a);
  }

  // Operator: signature is fixed, must not be flagged.
  bool operator >(Object unusedThree) => true;
}

class ChildService extends Service {
  // @override: signature is contractual, must not be flagged even if
  // the body ignores the parameter.
  @override
  void doWork(int a, int unusedFour) {
    print('child');
  }
}

class Box {
  final int width;
  final int height;
  // `this.x` parameters are auto-assigned; they don't need a body
  // reference. Must not be flagged.
  Box.dims(this.width, this.height);

  // Named constructor with a regular parameter that's never referenced.
  Box.tagged(int raw, String unusedFive) : width = raw, height = raw;
}

// A platform-interface style stub: body is only `throw
// UnimplementedError(...)`. Must NOT be flagged.
abstract class GestureExclusion {
  Future<void> setRects(List<int> rects) {
    throw UnimplementedError('setRects has not been implemented.');
  }
}
