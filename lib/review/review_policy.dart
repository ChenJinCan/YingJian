enum ReviewSuppressionReason {
  firstValueMissing,
  firstValueTooRecent,
  insufficientValueMoments,
  sessionFailure,
  versionAlreadyRequested,
  cooldownActive,
  taskInProgress,
}

final class ReviewPolicyInput {
  const ReviewPolicyInput({
    required this.now,
    required this.firstValueAt,
    required this.valueMomentCount,
    required this.lastRequestAt,
    required this.lastRequestedVersion,
    required this.currentVersion,
    required this.hasBlockingFailure,
    required this.taskInProgress,
  });

  final DateTime now;
  final DateTime? firstValueAt;
  final int valueMomentCount;
  final DateTime? lastRequestAt;
  final String? lastRequestedVersion;
  final String currentVersion;
  final bool hasBlockingFailure;
  final bool taskInProgress;
}

final class ReviewEligibility {
  const ReviewEligibility.eligible() : suppressionReason = null;
  const ReviewEligibility.suppressed(this.suppressionReason);

  final ReviewSuppressionReason? suppressionReason;
  bool get isEligible => suppressionReason == null;
}

final class ReviewPolicy {
  const ReviewPolicy({
    this.minimumValueAge = const Duration(days: 7),
    this.minimumValueMoments = 3,
    this.cooldown = const Duration(days: 90),
  });

  final Duration minimumValueAge;
  final int minimumValueMoments;
  final Duration cooldown;

  ReviewEligibility evaluate(ReviewPolicyInput input) {
    final firstValueAt = input.firstValueAt;
    if (firstValueAt == null) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.firstValueMissing,
      );
    }
    if (input.now.difference(firstValueAt) < minimumValueAge) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.firstValueTooRecent,
      );
    }
    if (input.valueMomentCount < minimumValueMoments) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.insufficientValueMoments,
      );
    }
    if (input.hasBlockingFailure) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.sessionFailure,
      );
    }
    if (input.taskInProgress) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.taskInProgress,
      );
    }
    if (input.lastRequestedVersion == input.currentVersion) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.versionAlreadyRequested,
      );
    }
    final lastRequestAt = input.lastRequestAt;
    if (lastRequestAt != null &&
        input.now.difference(lastRequestAt) < cooldown) {
      return const ReviewEligibility.suppressed(
        ReviewSuppressionReason.cooldownActive,
      );
    }
    return const ReviewEligibility.eligible();
  }
}
