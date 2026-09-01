import 'package:flutter/services.dart';
import 'package:yingjian/features/generation/application/generation_session_credential.dart';

/// Reads an already-authenticated, short-lived first-party session credential
/// from the platform host. This adapter never creates an identity, persists a
/// token, or falls back to a shared credential.
final class MethodChannelGenerationSessionCredentialSource
    implements GenerationSessionCredentialSource {
  const MethodChannelGenerationSessionCredentialSource({
    required this.baseUri,
    this.channel = const MethodChannel('yingjian/generation_session'),
  });

  final Uri baseUri;
  final MethodChannel channel;

  @override
  Future<GenerationSessionCredential?> currentCredential() async {
    final Map<String, Object?>? payload;
    try {
      payload = await channel.invokeMapMethod<String, Object?>(
        'getShortLivedBearerCredential',
        <String, Object>{'baseUrl': baseUri.toString()},
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'not_authenticated' || error.code == 'unavailable') {
        return null;
      }
      rethrow;
    }
    if (payload == null) return null;

    final bearerToken = payload['bearerToken'];
    final expiresAtEpochMilliseconds = payload['expiresAtEpochMilliseconds'];
    if (bearerToken is! String || expiresAtEpochMilliseconds is! int) {
      throw const FormatException(
        'Invalid generation session credential response',
      );
    }

    return GenerationSessionCredential(
      bearerToken: bearerToken,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtEpochMilliseconds,
        isUtc: true,
      ),
    );
  }
}
