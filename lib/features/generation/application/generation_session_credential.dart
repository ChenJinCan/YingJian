/// A short-lived, user-bound credential issued by the first-party session
/// service. The credential stays in memory and must never be persisted or
/// logged by the generation feature.
final class GenerationSessionCredential {
  GenerationSessionCredential({
    required String bearerToken,
    required DateTime expiresAt,
  }) : bearerToken = _validateBearerToken(bearerToken),
       expiresAt = expiresAt.toUtc();

  static const minimumRemainingLifetime = Duration(seconds: 30);
  static const maximumRemainingLifetime = Duration(hours: 1);

  final String bearerToken;
  final DateTime expiresAt;

  /// Returns the token only while it is both usable and observably
  /// short-lived. A source must refresh the credential instead of allowing a
  /// long-lived secret to cross this boundary.
  String? bearerTokenAt(DateTime now) {
    final remaining = expiresAt.difference(now.toUtc());
    if (remaining < minimumRemainingLifetime ||
        remaining > maximumRemainingLifetime) {
      return null;
    }
    return bearerToken;
  }

  static String _validateBearerToken(String value) {
    final token = value.trim();
    if (token.length < 16 ||
        token.length > 8192 ||
        !_bearerTokenPattern.hasMatch(token)) {
      throw const FormatException('Invalid generation session credential');
    }
    return token;
  }

  static final RegExp _bearerTokenPattern = RegExp(r'^[A-Za-z0-9\-._~+/]+=*$');
}

/// Supplier-neutral boundary for the app's authenticated user session.
///
/// Implementations may refresh the credential when needed. Returning `null`
/// means that no authenticated generation session is currently available.
abstract interface class GenerationSessionCredentialSource {
  Future<GenerationSessionCredential?> currentCredential();
}
