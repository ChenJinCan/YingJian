import 'package:yingjian/features/generation/application/generation_coordinator.dart';

/// Supplier-neutral user actions for a completed generated-media artifact.
///
/// Calling either operation represents a separate, explicit user action. A
/// generated result is never saved or played merely because it was created.
abstract interface class GeneratedMediaActions {
  Future<String> saveToPhotoLibrary(GeneratedMedia media);

  Future<void> previewMotion(GeneratedMedia media);
}
