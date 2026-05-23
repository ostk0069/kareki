// A simplified stand-in for the real-world Flutter `ScrollPhysics`
// situation: a base class declares a method, a subclass `@override`s
// it, the subclass is instantiated in production, but the override
// method is only invoked **by name** in test code (in production the
// framework would dispatch to it virtually).
abstract class BaseHandler {
  void applyTo();
}

class ProductionHandler implements BaseHandler {
  @override
  void applyTo() {
    // Real framework calls dispatch here via the BaseHandler interface;
    // no production source mentions the simple name `applyTo`.
  }
}
