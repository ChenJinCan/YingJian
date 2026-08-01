import 'dart:io';

import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/review/review_policy.dart';

enum ReviewPlatform { ios, android }

final class ReviewState {
  const ReviewState({
    this.firstValueAt,
    this.valueMomentCount = 0,
    this.lastRequestAt,
    this.lastRequestedVersion,
  });

  final DateTime? firstValueAt;
  final int valueMomentCount;
  final DateTime? lastRequestAt;
  final String? lastRequestedVersion;
}

abstract interface class ReviewStateStore {
  Future<ReviewState> load();
  Future<void> save(ReviewState state);
}

abstract interface class ReviewGateway {
  Future<bool> requestReview();
  Future<bool> openStoreListing();
}

abstract interface class ReviewAnalytics {
  Future<void> track(AnalyticsEvent event);
}

final class ReviewRequestResult {
  const ReviewRequestResult._({required this.requested, this.reason});

  const ReviewRequestResult.requested() : this._(requested: true);

  const ReviewRequestResult.suppressed(ReviewSuppressionReason reason)
    : this._(requested: false, reason: reason);

  const ReviewRequestResult.unavailable() : this._(requested: false);

  final bool requested;
  final ReviewSuppressionReason? reason;
}

final class ReviewManager {
  ReviewManager({
    required ReviewStateStore stateStore,
    required ReviewGateway gateway,
    required ReviewAnalytics analytics,
    required DateTime Function() now,
    required Future<String> Function() version,
    ReviewPolicy policy = const ReviewPolicy(),
    Duration requestDelay = const Duration(milliseconds: 700),
  }) : this._(
         stateStore: stateStore,
         gateway: gateway,
         analytics: analytics,
         now: now,
         version: version,
         policy: policy,
         requestDelay: requestDelay,
       );

  ReviewManager._({
    required this._stateStore,
    required this._gateway,
    required this._analytics,
    required this._now,
    required this._version,
    required this._policy,
    required this._requestDelay,
  });

  factory ReviewManager.production(AppObservability observability) {
    return ReviewManager(
      stateStore: SharedPreferencesReviewStateStore(),
      gateway: InAppReviewGateway(
        platform: Platform.isAndroid
            ? ReviewPlatform.android
            : ReviewPlatform.ios,
      ),
      analytics: ObservabilityReviewAnalytics(observability),
      now: DateTime.now,
      version: () async => (await PackageInfo.fromPlatform()).version,
    );
  }

  final ReviewStateStore _stateStore;
  final ReviewGateway _gateway;
  final ReviewAnalytics _analytics;
  final DateTime Function() _now;
  final Future<String> Function() _version;
  final ReviewPolicy _policy;
  final Duration _requestDelay;
  Future<ReviewRequestResult>? _requestInFlight;
  bool _hasBlockingFailure = false;

  Future<void> recordSuccessfulExport() async {
    final state = await _stateStore.load();
    final now = _now();
    await _stateStore.save(
      ReviewState(
        firstValueAt: state.firstValueAt ?? now,
        valueMomentCount: state.valueMomentCount + 1,
        lastRequestAt: state.lastRequestAt,
        lastRequestedVersion: state.lastRequestedVersion,
      ),
    );
  }

  void recordBlockingFailure() {
    _hasBlockingFailure = true;
  }

  Future<ReviewRequestResult> requestReviewIfEligible({
    bool taskInProgress = false,
  }) {
    final active = _requestInFlight;
    if (active != null) {
      return active;
    }
    final request = _requestReviewIfEligible(taskInProgress: taskInProgress);
    _requestInFlight = request;
    return request.whenComplete(() {
      if (identical(_requestInFlight, request)) {
        _requestInFlight = null;
      }
    });
  }

  Future<ReviewRequestResult> _requestReviewIfEligible({
    required bool taskInProgress,
  }) async {
    final version = await _version();
    final state = await _stateStore.load();
    final eligibility = _policy.evaluate(
      ReviewPolicyInput(
        now: _now(),
        firstValueAt: state.firstValueAt,
        valueMomentCount: state.valueMomentCount,
        lastRequestAt: state.lastRequestAt,
        lastRequestedVersion: state.lastRequestedVersion,
        currentVersion: version,
        hasBlockingFailure: _hasBlockingFailure,
        taskInProgress: taskInProgress,
      ),
    );
    if (!eligibility.isEligible) {
      final reason = eligibility.suppressionReason!;
      await _track(
        AnalyticsEventName.reviewSuppressed,
        version,
        reason: _reasonName(reason),
      );
      return ReviewRequestResult.suppressed(reason);
    }

    await _track(AnalyticsEventName.reviewEligible, version);
    await _stateStore.save(
      ReviewState(
        firstValueAt: state.firstValueAt,
        valueMomentCount: state.valueMomentCount,
        lastRequestAt: _now(),
        lastRequestedVersion: version,
      ),
    );
    await _track(AnalyticsEventName.reviewRequestAttempted, version);
    if (_requestDelay > Duration.zero) {
      await Future<void>.delayed(_requestDelay);
    }
    try {
      if (await _gateway.requestReview()) {
        return const ReviewRequestResult.requested();
      }
    } on Object {
      // Native review availability must never affect the export result.
    }
    await _track(
      AnalyticsEventName.reviewRequestUnavailable,
      version,
      reason: 'native_unavailable',
    );
    return const ReviewRequestResult.unavailable();
  }

  Future<bool> openStoreListing() async {
    final version = await _version();
    try {
      final opened = await _gateway.openStoreListing();
      if (opened) {
        await _track(AnalyticsEventName.reviewStoreLinkOpened, version);
      }
      return opened;
    } on Object {
      return false;
    }
  }

  Future<void> _track(String name, String version, {String? reason}) {
    return _analytics.track(
      AnalyticsEvent(
        name,
        parameters: <String, Object?>{
          AnalyticsParameter.versionBucket: _safeVersion(version),
          AnalyticsParameter.reason: ?reason,
        },
      ),
    );
  }

  String _safeVersion(String version) {
    final normalized = version
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'version_${normalized.isEmpty ? 'unknown' : normalized}';
  }

  String _reasonName(ReviewSuppressionReason reason) => switch (reason) {
    ReviewSuppressionReason.firstValueMissing => 'first_value_missing',
    ReviewSuppressionReason.firstValueTooRecent => 'first_value_too_recent',
    ReviewSuppressionReason.insufficientValueMoments =>
      'insufficient_value_moments',
    ReviewSuppressionReason.sessionFailure => 'session_failure',
    ReviewSuppressionReason.versionAlreadyRequested =>
      'version_already_requested',
    ReviewSuppressionReason.cooldownActive => 'cooldown_active',
    ReviewSuppressionReason.taskInProgress => 'task_in_progress',
  };
}

final class SharedPreferencesReviewStateStore implements ReviewStateStore {
  static const _firstValueKey = 'review.first_value_at';
  static const _valueCountKey = 'review.value_moment_count';
  static const _lastRequestKey = 'review.last_request_at';
  static const _lastVersionKey = 'review.last_requested_version';

  @override
  Future<ReviewState> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ReviewState(
      firstValueAt: _date(preferences.getInt(_firstValueKey)),
      valueMomentCount: preferences.getInt(_valueCountKey) ?? 0,
      lastRequestAt: _date(preferences.getInt(_lastRequestKey)),
      lastRequestedVersion: preferences.getString(_lastVersionKey),
    );
  }

  @override
  Future<void> save(ReviewState state) async {
    final preferences = await SharedPreferences.getInstance();
    final firstValueAt = state.firstValueAt;
    if (firstValueAt != null &&
        !await preferences.setInt(
          _firstValueKey,
          firstValueAt.millisecondsSinceEpoch,
        )) {
      throw StateError('Unable to persist first review value moment');
    }
    if (!await preferences.setInt(_valueCountKey, state.valueMomentCount)) {
      throw StateError('Unable to persist review value count');
    }
    final lastRequestAt = state.lastRequestAt;
    if (lastRequestAt != null &&
        !await preferences.setInt(
          _lastRequestKey,
          lastRequestAt.millisecondsSinceEpoch,
        )) {
      throw StateError('Unable to persist review request date');
    }
    final lastRequestedVersion = state.lastRequestedVersion;
    if (lastRequestedVersion != null &&
        !await preferences.setString(_lastVersionKey, lastRequestedVersion)) {
      throw StateError('Unable to persist review request version');
    }
  }

  DateTime? _date(int? milliseconds) => milliseconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

final class InAppReviewGateway implements ReviewGateway {
  InAppReviewGateway({
    required ReviewPlatform platform,
    InAppReview? review,
    String? iosAppStoreId,
  }) : this._(
         platform: platform,
         review: review ?? InAppReview.instance,
         iosAppStoreId:
             iosAppStoreId ?? const String.fromEnvironment('IOS_APP_STORE_ID'),
       );

  InAppReviewGateway._({
    required this._platform,
    required this._review,
    required this._iosAppStoreId,
  });

  final ReviewPlatform _platform;
  final InAppReview _review;
  final String _iosAppStoreId;

  @override
  Future<bool> requestReview() async {
    if (!await _review.isAvailable()) {
      return false;
    }
    await _review.requestReview();
    return true;
  }

  @override
  Future<bool> openStoreListing() async {
    if (_platform == ReviewPlatform.ios && _iosAppStoreId.isEmpty) {
      return false;
    }
    await _review.openStoreListing(
      appStoreId: _platform == ReviewPlatform.ios ? _iosAppStoreId : null,
    );
    return true;
  }
}

final class ObservabilityReviewAnalytics implements ReviewAnalytics {
  ObservabilityReviewAnalytics(this._observability);

  final AppObservability _observability;

  @override
  Future<void> track(AnalyticsEvent event) => _observability.track(event);
}
