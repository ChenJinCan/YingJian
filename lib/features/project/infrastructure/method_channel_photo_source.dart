import 'dart:async';

import 'package:flutter/services.dart';
import 'package:yingjian/features/project/infrastructure/app_owned_photo_importer.dart';

final class MethodChannelPhotoSource implements ReleasablePhotoSource {
  const MethodChannelPhotoSource({
    this.channel = const MethodChannel('yingjian/photo_picker'),
    this.selectionTimeout = const Duration(seconds: 105),
  });

  final MethodChannel channel;
  final Duration selectionTimeout;

  @override
  Future<List<SelectedPhoto>> pickPhotos({required int limit}) async {
    final values = await channel
        .invokeListMethod<Map<Object?, Object?>>('pickPhotos', <String, Object>{
          'limit': limit,
        })
        .timeout(selectionTimeout);
    return (values ?? const <Map<Object?, Object?>>[])
        .map(
          (value) => SelectedPhoto(
            path: value['path']! as String,
            name: value['name']! as String,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> releasePhotos(List<SelectedPhoto> photos) {
    return channel.invokeMethod<void>('discardPhotos', <String, Object>{
      'paths': photos.map((photo) => photo.path).toList(growable: false),
    });
  }
}
