import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef MediaDirectoryProvider = Future<Directory> Function();
typedef HeifSupportProvider = Future<bool> Function();

@immutable
class SelectedPhoto {
  const SelectedPhoto({required this.path, required this.name});

  final String path;
  final String name;
}

abstract interface class PhotoSource {
  Future<List<SelectedPhoto>> pickPhotos({required int limit});
}

final class AppOwnedPhotoImporter implements PhotoImporter {
  static const maxFileBytes = 100 * 1024 * 1024;
  static const maxPixelCount = 48 * 1000 * 1000;
  static const maxEdge = 12000;

  factory AppOwnedPhotoImporter({
    required PhotoSource source,
    required MediaDirectoryProvider mediaDirectory,
    HeifSupportProvider? supportsHeif,
    String Function()? createId,
  }) {
    return AppOwnedPhotoImporter._(
      source,
      mediaDirectory,
      supportsHeif ?? _defaultSupportsHeif,
      createId ?? _defaultId,
    );
  }

  AppOwnedPhotoImporter._(
    this._source,
    this._mediaDirectory,
    this._supportsHeif,
    this._createId,
  );

  final PhotoSource _source;
  final MediaDirectoryProvider _mediaDirectory;
  final HeifSupportProvider _supportsHeif;
  final String Function() _createId;

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    final selected = await _source.pickPhotos(limit: limit);
    if (selected.length > limit) {
      throw StateError('Photo source returned more than the requested limit');
    }
    if (selected.isEmpty) {
      return const PhotoImportBatch();
    }

    final directory = await _mediaDirectory();
    await directory.create(recursive: true);
    final imported = <ProjectPhoto>[];
    final failures = <PhotoImportFailure>[];
    for (final photo in selected) {
      try {
        await _validateInput(photo, supportsHeif: _supportsHeif);
        final id = _createId();
        final destination = File(
          '${directory.path}/$id${_extension(photo.name)}',
        );
        await File(photo.path).copy(destination.path);
        imported.add(
          ProjectPhoto(
            id: id,
            localPath: destination.path,
            originalName: photo.name,
          ),
        );
      } on _PhotoValidationException catch (error) {
        failures.add(
          PhotoImportFailure(photoName: photo.name, reason: error.reason),
        );
      } on FileSystemException {
        failures.add(
          PhotoImportFailure(
            photoName: photo.name,
            reason: PhotoImportFailureReason.copyFailed,
          ),
        );
      }
    }
    return PhotoImportBatch(photos: imported, failures: failures);
  }

  static Future<void> _validateInput(
    SelectedPhoto photo, {
    required HeifSupportProvider supportsHeif,
  }) async {
    final file = File(photo.path);
    RandomAccessFile? input;
    try {
      if (await file.length() > maxFileBytes) {
        throw const _PhotoValidationException(
          PhotoImportFailureReason.fileTooLarge,
        );
      }
      input = await file.open();
      final signature = await input.read(8);
      if (signature.length >= 2 &&
          signature[0] == 0xFF &&
          signature[1] == 0xD8) {
        await input.setPosition(2);
        await _validateJpeg(input);
        return;
      }
      if (_isPngSignature(signature)) {
        await _validatePng(input);
        return;
      }
      await input.setPosition(0);
      if (await _isHeif(input)) {
        if (!await supportsHeif()) {
          throw const _PhotoValidationException(
            PhotoImportFailureReason.unsupportedFormat,
          );
        }
        final dimensions = await _findHeifDimensions(
          input,
          start: 0,
          end: await input.length(),
          depth: 0,
        );
        if (dimensions == null) {
          throw const _PhotoValidationException(
            PhotoImportFailureReason.unreadable,
          );
        }
        _validateDimensions(dimensions.$1, dimensions.$2);
        return;
      }
      throw const _PhotoValidationException(
        PhotoImportFailureReason.unsupportedFormat,
      );
    } on FileSystemException {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.unreadable,
      );
    } finally {
      await input?.close();
    }
  }

  static Future<void> _validateJpeg(RandomAccessFile input) async {
    while (true) {
      var markerStart = await input.readByte();
      while (markerStart != -1 && markerStart != 0xFF) {
        markerStart = await input.readByte();
      }
      if (markerStart == -1) {
        break;
      }
      var marker = await input.readByte();
      while (marker == 0xFF) {
        marker = await input.readByte();
      }
      if (_isStartOfFrame(marker)) {
        final length = await _readUint16(input);
        if (length < 7) {
          break;
        }
        await input.readByte();
        final height = await _readUint16(input);
        final width = await _readUint16(input);
        if (width <= 0 || height <= 0) {
          break;
        }
        _validateDimensions(width, height);
        return;
      }
      if (marker == 0xD9 || marker == -1) {
        break;
      }
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
        continue;
      }
      final length = await _readUint16(input);
      if (length < 2) {
        break;
      }
      await input.setPosition(await input.position() + length - 2);
    }
    throw const _PhotoValidationException(PhotoImportFailureReason.unreadable);
  }

  static Future<void> _validatePng(RandomAccessFile input) async {
    var sawHeader = false;
    while (true) {
      final length = await _readUint32(input);
      final typeBytes = await input.read(4);
      if (length < 0 || typeBytes.length != 4) {
        break;
      }
      final type = String.fromCharCodes(typeBytes);
      if (type == 'IHDR') {
        if (sawHeader || length != 13) {
          break;
        }
        final width = await _readUint32(input);
        final height = await _readUint32(input);
        _validateDimensions(width, height);
        await input.setPosition(await input.position() + 5 + 4);
        sawHeader = true;
        continue;
      }
      if (type == 'acTL') {
        throw const _PhotoValidationException(
          PhotoImportFailureReason.animatedImage,
        );
      }
      if (type == 'IDAT') {
        if (sawHeader) {
          return;
        }
        break;
      }
      if (length > maxFileBytes) {
        break;
      }
      await input.setPosition(await input.position() + length + 4);
    }
    throw const _PhotoValidationException(PhotoImportFailureReason.unreadable);
  }

  static bool _isPngSignature(List<int> bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    return bytes.length == signature.length && listEquals(bytes, signature);
  }

  static Future<bool> _isHeif(RandomAccessFile input) async {
    await input.setPosition(0);
    final size = await _readUint32(input);
    final type = String.fromCharCodes(await input.read(4));
    if (size < 16 || type != 'ftyp') {
      return false;
    }
    final payload = await input.read((size - 8).clamp(0, 256));
    if (payload.length < 8) {
      return false;
    }
    final brands = <String>{String.fromCharCodes(payload.take(4))};
    for (var offset = 8; offset + 4 <= payload.length; offset += 4) {
      brands.add(String.fromCharCodes(payload.sublist(offset, offset + 4)));
    }
    const supported = {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'};
    return brands.any(supported.contains) &&
        !brands.contains('avif') &&
        !brands.contains('avis');
  }

  static Future<(int, int)?> _findHeifDimensions(
    RandomAccessFile input, {
    required int start,
    required int end,
    required int depth,
  }) async {
    if (depth > 8) {
      return null;
    }
    var offset = start;
    while (offset + 8 <= end) {
      await input.setPosition(offset);
      final size = await _readUint32(input);
      final typeBytes = await input.read(4);
      if (size < 8 || typeBytes.length != 4 || offset + size > end) {
        return null;
      }
      final type = String.fromCharCodes(typeBytes);
      final payloadStart = offset + 8;
      if (type == 'ispe' && size >= 20) {
        await input.setPosition(payloadStart + 4);
        final width = await _readUint32(input);
        final height = await _readUint32(input);
        return (width, height);
      }
      if (type == 'meta' || type == 'iprp' || type == 'ipco') {
        final childStart = payloadStart + (type == 'meta' ? 4 : 0);
        final result = await _findHeifDimensions(
          input,
          start: childStart,
          end: offset + size,
          depth: depth + 1,
        );
        if (result != null) {
          return result;
        }
      }
      offset += size;
    }
    return null;
  }

  static void _validateDimensions(int width, int height) {
    if (width <= 0 ||
        height <= 0 ||
        width > maxEdge ||
        height > maxEdge ||
        width * height > maxPixelCount) {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.dimensionsTooLarge,
      );
    }
  }

  static bool _isStartOfFrame(int marker) {
    return marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
  }

  static Future<int> _readUint16(RandomAccessFile input) async {
    final bytes = await input.read(2);
    if (bytes.length != 2) {
      return -1;
    }
    return (bytes[0] << 8) | bytes[1];
  }

  static Future<int> _readUint32(RandomAccessFile input) async {
    final bytes = await input.read(4);
    if (bytes.length != 4) {
      return -1;
    }
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || name.length - dot > 10) {
      return '';
    }
    final extension = name.substring(dot).toLowerCase();
    return RegExp(r'^\.[a-z0-9]+$').hasMatch(extension) ? extension : '';
  }

  static String _defaultId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final entropy = Random.secure().nextInt(0x100000000).toRadixString(16);
    return 'photo-$timestamp-$entropy';
  }

  static Future<bool> _defaultSupportsHeif() async {
    if (Platform.isIOS) {
      return true;
    }
    if (!Platform.isAndroid) {
      return false;
    }
    return await const MethodChannel(
          'yingjian/photo_input',
        ).invokeMethod<bool>('supportsHeif') ??
        false;
  }
}

final class _PhotoValidationException implements Exception {
  const _PhotoValidationException(this.reason);

  final PhotoImportFailureReason reason;
}
