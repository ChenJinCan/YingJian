abstract interface class SpeechTranscriber {
  Future<String> start({required String localeIdentifier});

  Future<void> stop();
}
