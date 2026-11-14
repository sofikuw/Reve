/// Retries a failed DNS lookup through a public DNS-over-HTTPS resolver.
///
/// Some phones return `Failed host lookup: api.github.com` for every GitHub
/// host — a broken private-DNS or VPN setting, or an over-eager ad-blocker —
/// while everything else resolves. Native builds get a fallback; the web build
/// cannot change how the browser resolves names, so the stub does nothing.
library;

export 'dns_fallback_stub.dart' if (dart.library.io) 'dns_fallback_io.dart';
