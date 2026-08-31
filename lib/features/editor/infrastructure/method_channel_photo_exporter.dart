import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';
import 'package:yingjian/features/editor/domain/edit_recipe.dart';
import 'package:yingjian/features/editor/domain/editing_core.dart';
import 'package:yingjian/features/editor/domain/image_pipeline_for_platform.dart';
import 'package:yingjian/features/editor/domain/legacy_edit_recipe_adapter.dart';
import 'package:yingjian/features/editor/domain/render_plan.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';

final class MethodChannelPhotoExporter
    implements
        CanonicalPhotoExporter,
        PhotoLibraryPermissionAwareExporter,
        PhotoLibrarySettingsOpener,
        PhotoExportStageAware,
        PhotoResultPreparer {
  MethodChannelPhotoExporter({
    this.channel = const MethodChannel('yingjian/photo_export'),
    this.shareChannel = const MethodChannel('yingjian/photo_share'),
    this.requestIdFactory,
  }) {
    channel.setMethodCallHandler(_handlePlatformCall);
  }

  final MethodChannel channel;
  final MethodChannel shareChannel;
  final String Function()? requestIdFactory;
  int _requestSequence = 0;
  @override
  final ValueNotifier<PhotoExportStage> stage = ValueNotifier(
    PhotoExportStage.preparing,
  );

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'exportStage') return null;
    final arguments = call.arguments;
    if (arguments is Map &&
        arguments['stage'] == PhotoExportStage.savingToPhotoLibrary.name) {
      stage.value = PhotoExportStage.savingToPhotoLibrary;
    }
    return null;
  }

  @override
  Future<void> openPhotoLibrarySettings() =>
      channel.invokeMethod<void>('openPhotoSettings');

  @override
  Future<ExportedPhoto> export({
    required ProjectPhoto photo,
    required EditRecipe recipe,
  }) => exportWithOptions(
    photo: photo,
    recipe: recipe,
    options: PhotoExportOptions.defaults,
  );

  @override
  Future<ExportedPhoto> exportWithOptions({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required PhotoExportOptions options,
  }) => exportCanonical(
    photo: photo,
    recipe: recipe,
    editState: const LegacyEditRecipeAdapter().read(recipe, photoId: photo.id),
    editContext: EditContext.ios,
    options: options,
  );

  @override
  Future<ExportedPhoto> exportCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) async {
    stage.value = PhotoExportStage.preparing;
    final response = await channel.invokeMapMethod<String, Object?>(
      'exportPhoto',
      _canonicalArguments(
        photo: photo,
        recipe: recipe,
        editState: editState,
        editContext: editContext,
        options: options,
      ),
    );
    if (response == null) {
      throw const FormatException('Photo export returned no result');
    }
    final assetId = response['assetId'];
    final width = response['width'];
    final height = response['height'];
    final sharePath = response['sharePath'];
    if (assetId is! String || width is! int || height is! int) {
      throw const FormatException('Photo export returned an invalid result');
    }
    if (sharePath != null && sharePath is! String) {
      throw const FormatException(
        'Photo export returned an invalid share path',
      );
    }
    return ExportedPhoto(
      assetId: assetId,
      width: width,
      height: height,
      sharePath: sharePath as String?,
    );
  }

  @override
  PhotoPreparation prepareCanonical({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) {
    final requestId =
        requestIdFactory?.call() ??
        'photo-prepare-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';
    final platformResult = _prepareCanonical(
      requestId: requestId,
      photo: photo,
      recipe: recipe,
      editState: editState,
      editContext: editContext,
      options: options,
    );
    return _MethodChannelPhotoPreparation(
      requestId: requestId,
      platformResult: platformResult,
      cancelRequest: () => channel.invokeMethod<void>(
        'cancelPhotoPreparation',
        <String, Object>{'requestId': requestId},
      ),
      discardPreparedPhoto: (prepared) async {
        try {
          await shareChannel.invokeMethod<void>('discardPhotos', {
            'localPaths': <String>[prepared.localPath],
          });
        } on Object {
          // Cancellation remains authoritative even when cleanup is unavailable.
        }
      },
    );
  }

  Future<PreparedPhoto> _prepareCanonical({
    required String requestId,
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) async {
    try {
      final response = await channel.invokeMapMethod<String, Object?>(
        'prepareSharePhoto',
        <String, Object?>{
          'requestId': requestId,
          ..._canonicalArguments(
            photo: photo,
            recipe: recipe,
            editState: editState,
            editContext: editContext,
            options: options,
          ),
        },
      );
      if (response == null || response['requestId'] != requestId) {
        throw const FormatException(
          'Photo preparation returned an invalid request identity',
        );
      }
      final sharePath = response['sharePath'];
      final width = response['width'];
      final height = response['height'];
      if (sharePath is! String ||
          sharePath.isEmpty ||
          width is! int ||
          width <= 0 ||
          height is! int ||
          height <= 0) {
        throw const FormatException(
          'Photo preparation returned an invalid result',
        );
      }
      return PreparedPhoto(
        requestId: requestId,
        localPath: sharePath,
        width: width,
        height: height,
      );
    } on PlatformException catch (error) {
      if (error.code == 'prepareCancelled') {
        throw const PhotoPreparationCanceled();
      }
      rethrow;
    }
  }

  Map<String, Object?> _canonicalArguments({
    required ProjectPhoto photo,
    required EditRecipe recipe,
    required EditState editState,
    required EditContext editContext,
    required PhotoExportOptions options,
  }) {
    final pipeline = imagePipelineForCurrentPlatform(
      recipe,
      sourceId: photo.id,
      editState: editState,
      context: editContext,
      outputRequirements: RenderOutputRequirements.export(
        format: options.format.name,
        quality: options.quality.name,
        maxEdge: options.size == PhotoExportSize.longEdge
            ? options.longEdgePixels
            : null,
      ),
    );
    return <String, Object?>{
      'sourcePath': photo.localPath,
      'pipeline': pipeline.toPlatformArguments(),
      'options': options.toPlatformArguments(),
    };
  }
}

final class _MethodChannelPhotoPreparation implements PhotoPreparation {
  _MethodChannelPhotoPreparation({
    required this.requestId,
    required Future<PreparedPhoto> platformResult,
    required this.cancelRequest,
    required this.discardPreparedPhoto,
  }) {
    _result = _publishResult(platformResult);
  }

  @override
  final String requestId;
  late final Future<PreparedPhoto> _result;
  @override
  Future<PreparedPhoto> get result => _result;
  final Future<void> Function() cancelRequest;
  final Future<void> Function(PreparedPhoto prepared) discardPreparedPhoto;
  bool _cancelRequested = false;

  Future<PreparedPhoto> _publishResult(
    Future<PreparedPhoto> platformResult,
  ) async {
    late final PreparedPhoto prepared;
    try {
      prepared = await platformResult;
    } on Object {
      if (_cancelRequested) throw const PhotoPreparationCanceled();
      rethrow;
    }
    if (!_cancelRequested) return prepared;
    await discardPreparedPhoto(prepared);
    throw const PhotoPreparationCanceled();
  }

  @override
  Future<void> cancel() async {
    if (_cancelRequested) return;
    _cancelRequested = true;
    await cancelRequest();
  }
}
