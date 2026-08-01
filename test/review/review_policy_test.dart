import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/review/review_policy.dart';

void main() {
  final now = DateTime.utc(2026, 8, 1);

  ReviewPolicyInput input({
    DateTime? firstValueAt,
    int valueMomentCount = 3,
    DateTime? lastRequestAt,
    String? lastRequestedVersion,
    bool hasBlockingFailure = false,
    bool taskInProgress = false,
  }) => ReviewPolicyInput(
    now: now,
    firstValueAt: firstValueAt ?? now.subtract(const Duration(days: 8)),
    valueMomentCount: valueMomentCount,
    lastRequestAt: lastRequestAt,
    lastRequestedVersion: lastRequestedVersion,
    currentVersion: '1.0.0',
    hasBlockingFailure: hasBlockingFailure,
    taskInProgress: taskInProgress,
  );

  test('allows a satisfied user after three value moments and seven days', () {
    expect(const ReviewPolicy().evaluate(input()).isEligible, isTrue);
  });

  test('blocks prompts during work, after failure, and inside cooldown', () {
    const policy = ReviewPolicy();

    expect(
      policy.evaluate(input(taskInProgress: true)).suppressionReason,
      ReviewSuppressionReason.taskInProgress,
    );
    expect(
      policy.evaluate(input(hasBlockingFailure: true)).suppressionReason,
      ReviewSuppressionReason.sessionFailure,
    );
    expect(
      policy
          .evaluate(input(lastRequestAt: now.subtract(const Duration(days: 2))))
          .suppressionReason,
      ReviewSuppressionReason.cooldownActive,
    );
  });

  test('blocks repeat prompts for the same version', () {
    expect(
      const ReviewPolicy()
          .evaluate(input(lastRequestedVersion: '1.0.0'))
          .suppressionReason,
      ReviewSuppressionReason.versionAlreadyRequested,
    );
  });
}
