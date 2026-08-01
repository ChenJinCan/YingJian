import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/observability_backend.dart';

enum ObservabilityStatus { disabled, initializing, enabled, unavailable }

final class AppObservability extends ChangeNotifier {
  AppObservability(this._backend);

  static const _maximumTrailLength = 20;
  static final _safeValue = RegExp(r'^[a-z0-9_]{1,40}$');

  final ObservabilityBackend _backend;
  final List<String> _recentTrail = <String>[];
  Future<bool>? _initialization;
  ObservabilityStatus _status = ObservabilityStatus.disabled;
  String? _currentScreen;

  ObservabilityStatus get status => _status;
  bool get collectionEnabled => _status == ObservabilityStatus.enabled;
  bool get available => _status != ObservabilityStatus.unavailable;
  List<String> get recentTrail => UnmodifiableListView(_recentTrail);

  Future<bool> initialize({required bool collectionEnabled}) async {
    if (!collectionEnabled) {
      _setStatus(ObservabilityStatus.disabled);
      return true;
    }
    return _enable();
  }

  Future<bool> setCollectionEnabled(bool enabled) async {
    if (!enabled) {
      _recentTrail.clear();
      if (_status == ObservabilityStatus.enabled) {
        try {
          await _backend.setCollectionEnabled(false);
        } on Object {
          // The in-memory privacy choice takes effect even if an SDK call fails.
        }
      }
      _setStatus(ObservabilityStatus.disabled);
      return true;
    }
    return _enable();
  }

  Future<bool> _enable() {
    final existing = _initialization;
    if (existing != null) {
      return existing;
    }
    final request = _initializeAndEnable();
    _initialization = request;
    return request.whenComplete(() {
      if (identical(_initialization, request)) {
        _initialization = null;
      }
    });
  }

  Future<bool> _initializeAndEnable() async {
    _setStatus(ObservabilityStatus.initializing);
    final initialized = await _backend.initialize();
    if (!initialized) {
      _setStatus(ObservabilityStatus.unavailable);
      return false;
    }
    try {
      await _backend.setCollectionEnabled(true);
    } on Object {
      _setStatus(ObservabilityStatus.unavailable);
      return false;
    }
    _setStatus(ObservabilityStatus.enabled);
    await track(AnalyticsEvent(AnalyticsEventName.appOpened));
    return true;
  }

  void installGlobalErrorHandlers() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterHandler?.call(details);
      if (collectionEnabled) {
        unawaited(
          recordError(
            details.exception,
            details.stack ?? StackTrace.current,
            fatal: true,
            reason: 'flutter_framework',
          ),
        );
      }
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      final previouslyHandled =
          previousPlatformHandler?.call(error, stackTrace) ?? false;
      if (!collectionEnabled) {
        return previouslyHandled;
      }
      unawaited(
        recordError(
          error,
          stackTrace,
          fatal: true,
          reason: 'platform_dispatcher',
        ),
      );
      return true;
    };
  }

  Future<void> trackScreen(String screen) async {
    final safeScreen = _sanitize(screen);
    if (safeScreen == null) {
      return;
    }
    _currentScreen = safeScreen;
    if (!collectionEnabled) {
      return;
    }
    _appendTrail('screen_viewed|screen=$safeScreen');
    try {
      await _backend.logScreenView(safeScreen);
    } on Object {
      // Observability is best effort and never owns product behavior.
    }
  }

  Future<void> track(AnalyticsEvent event) async {
    if (!collectionEnabled) {
      return;
    }
    final parameters = <String, Object>{};
    for (final entry in event.parameters.entries) {
      final value = _sanitizeParameter(entry.value);
      if (value != null) {
        parameters[entry.key] = value;
      }
    }
    final currentScreen = _currentScreen;
    if (currentScreen != null &&
        !parameters.containsKey(AnalyticsParameter.screen)) {
      parameters[AnalyticsParameter.screen] = currentScreen;
    }
    _appendTrail(event.name);
    try {
      await _backend.logEvent(event.name, parameters);
    } on Object {
      // Observability is best effort and never owns product behavior.
    }
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required bool fatal,
    required String reason,
  }) async {
    if (!collectionEnabled) {
      return;
    }
    final safeReason = _sanitize(reason) ?? 'unknown';
    final fingerprint = StateError('app_error_${error.runtimeType}');
    try {
      await _backend.recordError(
        fingerprint,
        stackTrace,
        fatal: fatal,
        reason: safeReason,
      );
    } on Object {
      // Crash reporting failure must not escape into product behavior.
    }
  }

  Future<T> traceOperation<T>({
    required String operation,
    required Future<T> Function() action,
    Map<String, String> attributes = const <String, String>{},
  }) async {
    if (!collectionEnabled) {
      return action();
    }
    final safeOperation = _sanitize(operation) ?? 'other';
    ObservabilityTrace? trace;
    try {
      trace = _backend.createTrace('operation_$safeOperation');
      var count = 0;
      for (final entry in attributes.entries) {
        if (count == 4) {
          break;
        }
        final name = _sanitize(entry.key);
        final value = _sanitize(entry.value);
        if (name != null && value != null) {
          trace.putAttribute(name, value);
          count++;
        }
      }
      await trace.start();
    } on Object {
      trace = null;
    }

    try {
      final result = await action();
      trace?.putAttribute('result', 'success');
      return result;
    } on Object {
      trace?.putAttribute('result', 'failure');
      rethrow;
    } finally {
      if (trace != null) {
        try {
          await trace.stop();
        } on Object {
          // The measured operation result always wins over telemetry failure.
        }
      }
    }
  }

  Object? _sanitizeParameter(Object? value) {
    if (value is bool || value is int || value is double) {
      return value;
    }
    if (value is String) {
      return _sanitize(value);
    }
    return null;
  }

  String? _sanitize(String value) {
    final normalized = value.trim().toLowerCase();
    return _safeValue.hasMatch(normalized) ? normalized : null;
  }

  void _appendTrail(String value) {
    _recentTrail.add(value);
    if (_recentTrail.length > _maximumTrailLength) {
      _recentTrail.removeAt(0);
    }
  }

  void _setStatus(ObservabilityStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    notifyListeners();
  }
}
