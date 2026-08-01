abstract final class AnalyticsEventName {
  static const appOpened = 'app_opened';
  static const screenViewed = 'screen_viewed';
  static const editorOpened = 'editor_opened';
  static const diagnosticsPreferenceChanged = 'diagnostics_preference_changed';
  static const reviewEligible = 'review_eligible';
  static const reviewSuppressed = 'review_suppressed';
  static const reviewRequestAttempted = 'review_request_attempted';
  static const reviewRequestUnavailable = 'review_request_unavailable';
  static const reviewStoreLinkOpened = 'review_store_link_opened';

  static const allowed = <String>{
    appOpened,
    screenViewed,
    editorOpened,
    diagnosticsPreferenceChanged,
    reviewEligible,
    reviewSuppressed,
    reviewRequestAttempted,
    reviewRequestUnavailable,
    reviewStoreLinkOpened,
  };
}

abstract final class AnalyticsParameter {
  static const screen = 'screen';
  static const source = 'source';
  static const feature = 'feature';
  static const action = 'action';
  static const result = 'result';
  static const reason = 'reason';
  static const provider = 'provider';
  static const countBucket = 'count_bucket';
  static const versionBucket = 'version_bucket';

  static const allowed = <String>{
    screen,
    source,
    feature,
    action,
    result,
    reason,
    provider,
    countBucket,
    versionBucket,
  };
}

final class AnalyticsEvent {
  AnalyticsEvent(
    this.name, {
    Map<String, Object?> parameters = const <String, Object?>{},
  }) : parameters = Map<String, Object?>.unmodifiable(parameters) {
    if (!AnalyticsEventName.allowed.contains(name)) {
      throw ArgumentError.value(name, 'name', 'Event is not allowlisted');
    }
    if (parameters.length > 12 ||
        parameters.keys.any(
          (key) => !AnalyticsParameter.allowed.contains(key),
        )) {
      throw ArgumentError.value(
        parameters.keys,
        'parameters',
        'Parameters must use approved keys',
      );
    }
  }

  final String name;
  final Map<String, Object?> parameters;
}
