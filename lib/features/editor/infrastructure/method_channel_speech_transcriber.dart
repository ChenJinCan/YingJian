import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/speech_transcriber.dart';

final class MethodChannelSpeechTranscriber implements SpeechTranscriber {
  const MethodChannelSpeechTranscriber();

  static const _channel = MethodChannel('yingjian/speech_transcription');

  @override
  Future<String> start({required String localeIdentifier}) async {
    final transcript = await _channel.invokeMethod<String>(
      'startTranscription',
      <String, Object>{'localeIdentifier': localeIdentifier},
    );
    if (transcript == null || transcript.trim().isEmpty) {
      throw StateError('Speech transcription returned no text');
    }
    return transcript.trim();
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stopTranscription');
}
