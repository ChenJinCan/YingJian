import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:yingjian/observability/observability_backend.dart';

final class FirebaseObservabilityBackend implements ObservabilityBackend {
  @override
  Future<bool> initialize() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return true;
    } on Object {
      // Native Firebase files are intentionally absent until an independent
      // Yingjian project is configured. Product startup must remain available.
      return false;
    }
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enabled);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enabled);
    await FirebasePerformance.instance.setPerformanceCollectionEnabled(enabled);
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    return FirebaseAnalytics.instance.logEvent(
      name: name,
      parameters: parameters,
    );
  }

  @override
  Future<void> logScreenView(String screenName) {
    return FirebaseAnalytics.instance.logScreenView(screenName: screenName);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required bool fatal,
    required String reason,
  }) {
    return FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      fatal: fatal,
      reason: reason,
    );
  }

  @override
  ObservabilityTrace createTrace(String name) {
    return FirebaseObservabilityTrace(
      FirebasePerformance.instance.newTrace(name),
    );
  }
}

final class FirebaseObservabilityTrace implements ObservabilityTrace {
  FirebaseObservabilityTrace(this._trace);

  final Trace _trace;

  @override
  void putAttribute(String name, String value) {
    _trace.putAttribute(name, value);
  }

  @override
  Future<void> start() => _trace.start();

  @override
  Future<void> stop() => _trace.stop();
}
