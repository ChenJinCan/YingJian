import 'package:yingjian/features/creation/domain/creation_capability.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';

/// Safe production fallback when no authenticated first-party backend exists.
///
/// This adapter never uploads, queues, charges, retries, or substitutes another
/// capability.
final class UnavailableGenerationProvider implements GenerationProvider {
  const UnavailableGenerationProvider();

  @override
  Set<CreationCapability> get availableCapabilities => const {};

  @override
  Future<void> refreshCapabilities() async {}

  @override
  GenerationOffer offerFor(CreationCapability capability) =>
      throw GenerationCapabilityUnavailable(capability);

  @override
  Future<GenerationJob> create({
    required GenerationSourceSnapshot snapshot,
    required String clientRequestId,
    required GenerationConsent? consent,
  }) => Future.error(GenerationCapabilityUnavailable(snapshot.capability));

  @override
  Future<GenerationJob> cancel(GenerationJob job) =>
      Future.error(GenerationCannotCancel(job.id));

  @override
  Stream<GenerationJob> observe(GenerationJob job) =>
      Stream.error(GenerationCapabilityUnavailable(job.capability));
}
