abstract interface class ObservabilityTrace {
  void putAttribute(String name, String value);
  Future<void> start();
  Future<void> stop();
}

abstract interface class ObservabilityBackend {
  Future<bool> initialize();

  Future<void> setCollectionEnabled(bool enabled);

  Future<void> logEvent(String name, Map<String, Object> parameters);

  Future<void> logScreenView(String screenName);

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required bool fatal,
    required String reason,
  });

  ObservabilityTrace createTrace(String name);
}
