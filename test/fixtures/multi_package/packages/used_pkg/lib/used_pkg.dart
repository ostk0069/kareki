String hello() => 'hello from used_pkg';

// Public symbol that is never referenced from any other package.
String unreferencedAcrossPackages() => 'orphan';
