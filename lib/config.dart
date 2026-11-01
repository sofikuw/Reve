/// Compile-time configuration.
///
/// Pass values with `--dart-define`, for example:
///
///   flutter build apk --dart-define=OAUTH_CLIENT_ID=Iv1.abc123 \
///                     --dart-define=OAUTH_BACKEND=https://reve-oauth.example.workers.dev
///
/// The OAuth client ID is public (a client *secret* must never ship in the app).
/// The backend is only needed for the browser popup flow; the Android build uses
/// GitHub's device flow, which talks to github.com directly.
class AppConfig {
  const AppConfig._();

  /// Public client ID of the OAuth App (safe to ship; it is not a secret).
  /// Override at build time with `--dart-define=OAUTH_CLIENT_ID=…`.
  static const String oauthClientId =
      String.fromEnvironment('OAUTH_CLIENT_ID', defaultValue: 'Ov23liKqKI4YQP1Ie3OQ');

  static const String oauthBackend =
      String.fromEnvironment('OAUTH_BACKEND', defaultValue: '');

  static const String oauthScope =
      String.fromEnvironment('OAUTH_SCOPE', defaultValue: 'repo');

  static bool get hasOAuthClient => oauthClientId.isNotEmpty;
  static bool get hasOAuthBackend => oauthBackend.isNotEmpty;
}
