import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/photo_sharer.dart';

final class MethodChannelPhotoSharer implements PhotoSharer {
  const MethodChannelPhotoSharer({
    this.channel = const MethodChannel('yingjian/photo_share'),
  });

  final MethodChannel channel;

  @override
  Future<PhotoShareOutcome> share({required List<String> localPaths}) async {
    if (localPaths.isEmpty || localPaths.length > 6) {
      throw ArgumentError.value(localPaths, 'localPaths');
    }
    final result = await channel.invokeMethod<String>('sharePhotos', {
      'localPaths': List<String>.unmodifiable(localPaths),
    });
    return switch (result) {
      'completed' => PhotoShareOutcome.completed,
      'canceled' => PhotoShareOutcome.canceled,
      _ => throw const FormatException(
        'Photo share returned an invalid result',
      ),
    };
  }

  @override
  Future<void> discard({required List<String> localPaths}) async {
    if (localPaths.isEmpty) return;
    if (localPaths.length > 6) {
      throw ArgumentError.value(localPaths, 'localPaths');
    }
    await channel.invokeMethod<void>('discardPhotos', {
      'localPaths': List<String>.unmodifiable(localPaths),
    });
  }
}
