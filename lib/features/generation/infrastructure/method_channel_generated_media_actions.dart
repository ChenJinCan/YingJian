import 'package:flutter/services.dart';
import 'package:yingjian/features/generation/application/generated_media_actions.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';

final class MethodChannelGeneratedMediaActions
    implements GeneratedMediaActions {
  const MethodChannelGeneratedMediaActions({
    this.channel = const MethodChannel('yingjian/generated_media_actions'),
  });

  final MethodChannel channel;

  @override
  Future<String> saveToPhotoLibrary(GeneratedMedia media) async {
    _validateMedia(media);
    final response = await channel.invokeMapMethod<String, Object?>(
      'saveToPhotoLibrary',
      _arguments(media),
    );
    final assetId = response?['assetId'];
    if (assetId is! String || assetId.trim().isEmpty) {
      throw const FormatException(
        'Saving generated media returned an invalid asset identity',
      );
    }
    return assetId;
  }

  @override
  Future<void> previewMotion(GeneratedMedia media) async {
    _validateMedia(media);
    if (media.kind != GeneratedMediaKind.imageMotion) {
      throw ArgumentError.value(
        media.kind,
        'media.kind',
        'Only generated MP4 motion media can be previewed',
      );
    }
    await channel.invokeMethod<void>('previewMotion', _arguments(media));
  }

  static Map<String, Object> _arguments(GeneratedMedia media) =>
      <String, Object>{'path': media.localPath, 'kind': media.kind.name};

  static void _validateMedia(GeneratedMedia media) {
    final path = media.localPath;
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        'media.localPath',
        'Generated media requires an absolute local file path',
      );
    }
    final extension = path.split('.').last.toLowerCase();
    final validExtension = switch (media.kind) {
      GeneratedMediaKind.image => const <String>{
        'jpg',
        'jpeg',
        'png',
        'heic',
        'heif',
      }.contains(extension),
      GeneratedMediaKind.imageMotion => extension == 'mp4',
    };
    if (!validExtension) {
      throw ArgumentError.value(
        path,
        'media.localPath',
        'Generated media kind and file extension do not match',
      );
    }
  }
}
