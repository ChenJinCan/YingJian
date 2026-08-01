import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/review/review_manager.dart';
import 'package:yingjian/review/review_policy.dart';

void main() {
  test(
    'records value moments and requests review only when eligible',
    () async {
      final now = DateTime.utc(2026, 8, 1);
      final store = _MemoryStore(
        ReviewState(
          firstValueAt: now.subtract(const Duration(days: 8)),
          valueMomentCount: 2,
        ),
      );
      final gateway = _Gateway();
      final analytics = _Analytics();
      final manager = ReviewManager(
        stateStore: store,
        gateway: gateway,
        analytics: analytics,
        now: () => now,
        version: () async => '1.0.0',
        requestDelay: Duration.zero,
      );

      await manager.recordSuccessfulExport();
      final result = await manager.requestReviewIfEligible();

      expect(result.requested, isTrue);
      expect(gateway.reviewRequests, 1);
      expect(store.state.lastRequestedVersion, '1.0.0');
      expect(
        analytics.events,
        containsAll([
          AnalyticsEventName.reviewEligible,
          AnalyticsEventName.reviewRequestAttempted,
        ]),
      );
    },
  );

  test(
    'persistent store action never consumes a native prompt request',
    () async {
      final gateway = _Gateway();
      final manager = ReviewManager(
        stateStore: _MemoryStore(const ReviewState()),
        gateway: gateway,
        analytics: _Analytics(),
        now: DateTime.now,
        version: () async => '1.0.0',
        requestDelay: Duration.zero,
      );

      expect(await manager.openStoreListing(), isTrue);
      expect(gateway.storeOpens, 1);
      expect(gateway.reviewRequests, 0);
    },
  );

  test('blocking failure suppresses an otherwise eligible prompt', () async {
    final now = DateTime.utc(2026, 8, 1);
    final gateway = _Gateway();
    final manager = ReviewManager(
      stateStore: _MemoryStore(
        ReviewState(
          firstValueAt: now.subtract(const Duration(days: 8)),
          valueMomentCount: 3,
        ),
      ),
      gateway: gateway,
      analytics: _Analytics(),
      now: () => now,
      version: () async => '1.0.0',
      requestDelay: Duration.zero,
    );
    manager.recordBlockingFailure();

    final result = await manager.requestReviewIfEligible();

    expect(result.reason, ReviewSuppressionReason.sessionFailure);
    expect(gateway.reviewRequests, 0);
  });
}

final class _MemoryStore implements ReviewStateStore {
  _MemoryStore(this.state);

  ReviewState state;

  @override
  Future<ReviewState> load() async => state;

  @override
  Future<void> save(ReviewState state) async {
    this.state = state;
  }
}

final class _Gateway implements ReviewGateway {
  int reviewRequests = 0;
  int storeOpens = 0;

  @override
  Future<bool> requestReview() async {
    reviewRequests++;
    return true;
  }

  @override
  Future<bool> openStoreListing() async {
    storeOpens++;
    return true;
  }
}

final class _Analytics implements ReviewAnalytics {
  final List<String> events = [];

  @override
  Future<void> track(AnalyticsEvent event) async {
    events.add(event.name);
  }
}
