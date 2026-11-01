import 'package:flutter/foundation.dart' show kIsWeb;

/// Compile-time configuration.
///
/// Pass values with `--dart-define`, for example:
///
///   flutter build apk --dart-define=OAUTH_CLIENT_ID=Iv1.abc123 \
///                     --dart-define=OAUTH_BACKEND=https://reve-oauth.example.workers.dev
///
/// The OAuth client ID is public (a client *secret* must never ship in the app).
/// The backend is only needed in the browser, where GitHub's device-code
/// endpoints are blocked by CORS; native builds talk to github.com directly.
class AppConfig {
  const AppConfig._();

  /// Public client ID of the OAuth App (safe to ship; it is not a secret).
  /// Override at build time with `--dart-define=OAUTH_CLIENT_ID=…`.
  static const String oauthClientId =
      String.fromEnvironment('OAUTH_CLIENT_ID', defaultValue: 'Ov23liKqKI4YQP1Ie3OQ');

  /// Same broker the web app ships with. Only used when running in a browser:
  /// proxying native traffic through it would add nothing.
  static const String _defaultWebBroker =
      'https://reve-oauth.sofikuw.workers.dev';

  static const String _oauthBackenddefine =
      String.fromEnvironment('OAUTH_BACKEND', defaultValue: '');

  static String get oauthBackend =>
      _oauthBackenddefine.isNotEmpty ? _oauthBackenddefine : _defaultWebBroker;

  static const String oauthScope =
      String.fromEnvironment('OAUTH_SCOPE', defaultValue: 'repo');

  static bool get hasOAuthClient => oauthClientId.isNotEmpty;
  static bool get hasOAuthBackend => oauthBackend.isNotEmpty;

  /// Where device-flow calls should go: null means "talk to github.com".
  static String? get deviceFlowBackend => kIsWeb ? oauthBackend : null;
}
