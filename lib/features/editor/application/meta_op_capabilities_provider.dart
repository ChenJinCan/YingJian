import 'package:yingjian/features/editor/domain/meta_op_availability.dart';

abstract interface class MetaOpCapabilitiesProvider {
  Future<PlatformMetaOpCapabilities> load();
}

final class StaticMetaOpCapabilitiesProvider
    implements MetaOpCapabilitiesProvider {
  const StaticMetaOpCapabilitiesProvider(this.capabilities);

  final PlatformMetaOpCapabilities capabilities;

  @override
  Future<PlatformMetaOpCapabilities> load() async => capabilities;
}
