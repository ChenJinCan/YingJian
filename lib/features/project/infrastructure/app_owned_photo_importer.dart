import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/domain/content_sha256.dart';
import 'package:yingjian/features/editor/domain/editing_resource.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

typedef MediaDirectoryProvider = Future<Directory> Function();
typedef HeifSupportProvider = Future<bool> Function();
typedef PhotoInspectionProvider =
    Future<PhotoContentInspection> Function(String path);

@immutable
class PhotoContentInspection {
  const PhotoContentInspection({
    required this.contentSha256,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.orientation,
    required this.colorSpace,
    required this.inputFormat,
  });

  final String contentSha256;
  final int pixelWidth;
  final int pixelHeight;
  final int orientation;
  final PhotoColorSpace colorSpace;
  final PhotoInputFormat inputFormat;
}

@immutable
class SelectedPhoto {
  const SelectedPhoto({required this.path, required this.name});

  final String path;
  final String name;
}

abstract interface class PhotoSource {
  Future<List<SelectedPhoto>> pickPhotos({required int limit});
}

abstract interface class ReleasablePhotoSource implements PhotoSource {
  Future<void> releasePhotos(List<SelectedPhoto> photos);
}

abstract interface class CancelablePhotoSource implements PhotoSource {
  Future<void> cancelPick();
}

final class AppOwnedPhotoImporter
    implements EditingResourceImporter, CancelablePhotoImporter {
  static const maxFileBytes = 100 * 1024 * 1024;
  static const maxPixelCount = 48 * 1000 * 1000;
  static const maxEdge = 12000;

  factory AppOwnedPhotoImporter({
    required PhotoSource source,
    required MediaDirectoryProvider mediaDirectory,
    HeifSupportProvider? supportsHeif,
    PhotoInspectionProvider? inspectPhoto,
    String Function()? createId,
  }) {
    return AppOwnedPhotoImporter._(
      source,
      mediaDirectory,
      supportsHeif ?? _defaultSupportsHeif,
      inspectPhoto ?? _defaultInspectPhoto,
      createId ?? _defaultId,
    );
  }

  AppOwnedPhotoImporter._(
    this._source,
    this._mediaDirectory,
    this._supportsHeif,
    this._inspectPhoto,
    this._createId,
  );

  final PhotoSource _source;
  final MediaDirectoryProvider _mediaDirectory;
  final HeifSupportProvider _supportsHeif;
  final PhotoInspectionProvider _inspectPhoto;
  final String Function() _createId;
  final Set<_PhotoImportOperation> _activeImports = {};

  @override
  Future<void> cancelImport() async {
    for (final operation in _activeImports.toList(growable: false)) {
      operation.isCanceled = true;
    }
    final source = _source;
    if (source is CancelablePhotoSource) await source.cancelPick();
  }

  @override
  Future<PhotoImportBatch> importPhotos({required int limit}) async {
    final operation = _PhotoImportOperation();
    _activeImports.add(operation);
    var selected = const <SelectedPhoto>[];
    var completedBatch = const PhotoImportBatch();
    try {
      selected = await _source.pickPhotos(limit: limit);
      _checkCanceled(operation);
      if (selected.length > limit) {
        throw StateError('Photo source returned more than the requested limit');
      }
      if (selected.isEmpty) {
        return const PhotoImportBatch();
      }

      final directory = await _mediaDirectory();
      _checkCanceled(operation);
      await directory.create(recursive: true);
      _checkCanceled(operation);
      await _cleanupAbandonedImports(directory);
      _checkCanceled(operation);
      final imported = <ProjectPhoto>[];
      final failures = <PhotoImportFailure>[];
      for (final photo in selected) {
        _checkCanceled(operation);
        File? destination;
        try {
          await _validateInput(photo, supportsHeif: _supportsHeif);
          _checkCanceled(operation);
          final id = _createId();
          destination = File('${directory.path}/$id.importing');
          operation.ownedPaths.add(destination.path);
          await File(photo.path).copy(destination.path);
          _checkCanceled(operation);
          await _validateInput(
            SelectedPhoto(path: destination.path, name: photo.name),
            supportsHeif: _supportsHeif,
          );
          _checkCanceled(operation);
          final inspection = await _inspectPhoto(destination.path);
          _checkCanceled(operation);
          _validateInspection(inspection);
          final finalCopy = File(
            '${directory.path}/$id${_extensionFor(inspection.inputFormat)}',
          );
          operation.ownedPaths.add(finalCopy.path);
          await destination.rename(finalCopy.path);
          _checkCanceled(operation);
          destination = finalCopy;
          imported.add(
            ProjectPhoto(
              id: id,
              localPath: destination.path,
              originalName: photo.name,
              contentSha256: inspection.contentSha256,
              pixelWidth: inspection.pixelWidth,
              pixelHeight: inspection.pixelHeight,
              orientation: inspection.orientation,
              colorSpace: inspection.colorSpace,
              inputFormat: inspection.inputFormat,
              supportState: PhotoSupportState.supported,
            ),
          );
        } on _PhotoValidationException catch (error) {
          await _deleteIfExists(destination);
          failures.add(
            PhotoImportFailure(photoName: photo.name, reason: error.reason),
          );
        } on PlatformException catch (error) {
          await _deleteIfExists(destination);
          failures.add(
            PhotoImportFailure(
              photoName: photo.name,
              reason: error.code == 'unsupportedColorSpace'
                  ? PhotoImportFailureReason.unsupportedColorSpace
                  : PhotoImportFailureReason.unreadable,
            ),
          );
        } on FileSystemException {
          await _deleteIfExists(destination);
          failures.add(
            PhotoImportFailure(
              photoName: photo.name,
              reason: PhotoImportFailureReason.copyFailed,
            ),
          );
        }
      }
      completedBatch = PhotoImportBatch(photos: imported, failures: failures);
    } on _PhotoImportCanceled {
      await _deleteOwnedCopies(operation);
      completedBatch = const PhotoImportBatch();
    } finally {
      final source = _source;
      if (selected.isNotEmpty && source is ReleasablePhotoSource) {
        try {
          await source.releasePhotos(selected);
        } catch (_) {
          for (final photo in completedBatch.photos) {
            await _deleteIfExists(File(photo.localPath));
          }
          _activeImports.remove(operation);
          rethrow;
        }
      }
      _activeImports.remove(operation);
    }
    if (operation.isCanceled) {
      await _deleteOwnedCopies(operation);
      return const PhotoImportBatch();
    }
    return completedBatch;
  }

  @override
  Future<ImportedEditingResource?> importEditingResource(
    EditingResourceKind kind,
  ) async {
    final batch = await importPhotos(limit: 1);
    if (batch.photos.isEmpty) return null;
    final imported = batch.photos.single;
    final temporary = File(imported.localPath);
    try {
      final media = await _mediaDirectory();
      final sha = imported.contentSha256;
      final extension = _extensionFor(imported.inputFormat);
      final relativePath = 'resources/${sha.substring(0, 2)}/$sha$extension';
      final destination = File('${media.parent.path}/$relativePath');
      await destination.parent.create(recursive: true);
      if (await destination.exists()) {
        await _deleteIfExists(temporary);
      } else {
        await temporary.rename(destination.path);
      }
      final descriptor = EditingResourceDescriptor(
        id: 'resource-v1-$sha',
        kind: kind,
        relativePath: relativePath,
        contentSha256: sha,
        byteLength: await destination.length(),
      );
      descriptor.validate();
      return ImportedEditingResource(
        descriptor: descriptor,
        localPath: destination.path,
      );
    } on Object {
      await _deleteIfExists(temporary);
      rethrow;
    }
  }

  @override
  Future<ImportedEditingResource> storeEditingResource({
    required EditingResourceKind kind,
    required List<int> bytes,
    String extension = '.json',
    Object? payload,
  }) async {
    if (bytes.isEmpty || !RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)) {
      throw ArgumentError('Invalid editing resource payload');
    }
    final sha = ContentSha256.ofBytes(bytes);
    final relativePath = 'resources/${sha.substring(0, 2)}/$sha$extension';
    final media = await _mediaDirectory();
    final destination = File('${media.parent.path}/$relativePath');
    await destination.parent.create(recursive: true);
    if (!await destination.exists()) {
      final temporary = File('${destination.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(destination.path);
      } on FileSystemException {
        if (!await destination.exists()) rethrow;
        await _deleteIfExists(temporary);
      }
    }
    final descriptor = EditingResourceDescriptor(
      id: 'resource-v1-$sha',
      kind: kind,
      relativePath: relativePath,
      contentSha256: sha,
      byteLength: bytes.length,
    );
    descriptor.validate();
    return ImportedEditingResource(
      descriptor: descriptor,
      localPath: destination.path,
      payload: payload,
    );
  }

  @override
  Future<void> discardEditingResource(ImportedEditingResource resource) async {
    resource.descriptor.validate();
    final media = await _mediaDirectory();
    final root = Directory('${media.parent.path}/resources');
    final file = File(resource.localPath);
    if (!await root.exists() || !await file.exists()) return;
    final safeRoot = await root.resolveSymbolicLinks();
    final safePath = await file.resolveSymbolicLinks();
    if (safePath.startsWith('$safeRoot${Platform.pathSeparator}')) {
      await file.delete();
    }
  }

  static Future<void> _deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // The import failure remains item-scoped even if best-effort cleanup fails.
    }
  }

  static void _checkCanceled(_PhotoImportOperation operation) {
    if (operation.isCanceled) throw const _PhotoImportCanceled();
  }

  static Future<void> _deleteOwnedCopies(
    _PhotoImportOperation operation,
  ) async {
    for (final path in operation.ownedPaths) {
      await _deleteIfExists(File(path));
    }
  }

  Future<void> _cleanupAbandonedImports(Directory directory) async {
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.importing')) continue;
        if (_isActiveImportPath(entity.path)) continue;
        try {
          if (!await entity.exists() || _isActiveImportPath(entity.path)) {
            continue;
          }
          await entity.delete();
        } on FileSystemException {
          // A later import can retry cleanup without blocking this selection.
        }
      }
    } on FileSystemException {
      // Importing the selected photo remains useful if stale cleanup is denied.
    }
  }

  bool _isActiveImportPath(String path) {
    return _activeImports.any(
      (operation) => operation.ownedPaths.contains(path),
    );
  }

  static void _validateInspection(PhotoContentInspection inspection) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(inspection.contentSha256) ||
        inspection.orientation < 1 ||
        inspection.orientation > 8 ||
        inspection.inputFormat == PhotoInputFormat.unknown) {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.unreadable,
      );
    }
    _validateDimensions(inspection.pixelWidth, inspection.pixelHeight);
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
    const sequenceBrands = {'hevc', 'hevx', 'msf1'};
    if (brands.any(sequenceBrands.contains)) {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.animatedImage,
      );
    }
    const supported = {'heic', 'heix', 'mif1'};
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

  static String _extensionFor(PhotoInputFormat format) {
    return switch (format) {
      PhotoInputFormat.jpeg => '.jpg',
      PhotoInputFormat.png => '.png',
      PhotoInputFormat.heic => '.heic',
      PhotoInputFormat.unknown => '',
    };
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

  static Future<PhotoContentInspection> _defaultInspectPhoto(
    String path,
  ) async {
    final raw = await const MethodChannel(
      'yingjian/photo_input',
    ).invokeMapMethod<String, Object?>('inspectPhoto', {'path': path});
    if (raw == null) {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.unreadable,
      );
    }
    final contentSha256 = raw['contentSha256'];
    final pixelWidth = raw['pixelWidth'];
    final pixelHeight = raw['pixelHeight'];
    final orientation = raw['orientation'];
    if (contentSha256 is! String ||
        pixelWidth is! num ||
        pixelHeight is! num ||
        orientation is! num) {
      throw const _PhotoValidationException(
        PhotoImportFailureReason.unreadable,
      );
    }
    T enumValue<T extends Enum>(Object? name, List<T> values, T fallback) {
      return values.where((value) => value.name == name).firstOrNull ??
          fallback;
    }

    return PhotoContentInspection(
      contentSha256: contentSha256,
      pixelWidth: pixelWidth.toInt(),
      pixelHeight: pixelHeight.toInt(),
      orientation: orientation.toInt(),
      colorSpace: enumValue(
        raw['colorSpace'],
        PhotoColorSpace.values,
        PhotoColorSpace.unknown,
      ),
      inputFormat: enumValue(
        raw['inputFormat'],
        PhotoInputFormat.values,
        PhotoInputFormat.unknown,
      ),
    );
  }
}

final class _PhotoImportOperation {
  bool isCanceled = false;
  final Set<String> ownedPaths = {};
}

final class _PhotoImportCanceled implements Exception {
  const _PhotoImportCanceled();
}

final class _PhotoValidationException implements Exception {
  const _PhotoValidationException(this.reason);

  final PhotoImportFailureReason reason;
}
