import 'package:flutter/services.dart';
import 'package:yingjian/features/editor/application/meta_op_capabilities_provider.dart';
import 'package:yingjian/features/editor/domain/meta_op.dart';
import 'package:yingjian/features/editor/domain/meta_op_availability.dart';

final class MethodChannelMetaOpCapabilities
    implements MetaOpCapabilitiesProvider {
  MethodChannelMetaOpCapabilities({
    this.channel = const MethodChannel('yingjian/photo_preview'),
  });

  final MethodChannel channel;

  @override
  Future<PlatformMetaOpCapabilities> load() async {
    final response = await channel.invokeMapMethod<String, Object?>(
      'getMetaOpCapabilities',
    );
    if (response == null) {
      throw const FormatException('Platform returned no meta-op capabilities');
    }
    final platform = switch (response['platform']) {
      'ios' => EditPlatform.ios,
      'android' => EditPlatform.android,
      _ => throw const FormatException('Invalid capability platform'),
    };
    final rawOperations = response['operations'];
    if (rawOperations is! List) {
      throw const FormatException('Invalid meta-op capability list');
    }
    final entries = <MetaOpExecutionSupport>[];
    final identities = <String>{};
    for (final rawOperation in rawOperations) {
      if (rawOperation is! Map) {
        throw const FormatException('Invalid meta-op capability entry');
      }
      final operation = Map<String, Object?>.from(rawOperation);
      final id = operation['id'];
      final version = operation['version'];
      final preview = operation['preview'];
      final export = operation['export'];
      final maxTargets = operation['maxTargets'];
      final maxResourceBytes = operation['maxResourceBytes'];
      if (id is! String ||
          id.trim().isEmpty ||
          version is! int ||
          version < 1 ||
          preview is! bool ||
          export is! bool ||
          maxTargets is! int ||
          maxTargets < 0 ||
          maxResourceBytes is! int ||
          maxResourceBytes < 0 ||
          !identities.add('$id@$version')) {
        throw const FormatException('Invalid meta-op capability entry');
      }
      entries.add(
        MetaOpExecutionSupport(
          metaOpId: id,
          metaOpVersion: version,
          preview: preview,
          export: export,
          maxTargets: maxTargets,
          maxResourceBytes: maxResourceBytes,
        ),
      );
    }
    return PlatformMetaOpCapabilities(platform: platform, entries: entries);
  }
}
