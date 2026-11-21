/// No-op for the web build: the browser owns name resolution.
void installDnsFallback() {}

/// No-op for the web build.
Future<void> preResolve(String host) async {}
