import 'package:flutter_test/flutter_test.dart';
import 'package:yingjian/features/editor/application/photo_exporter.dart';

void main() {
  test('default export is original-size high-quality JPEG in sRGB', () {
    expect(PhotoExportOptions.defaults.toPlatformArguments(), {
      'format': 'jpeg',
      'size': 'original',
      'quality': 'high',
      'colorSpace': 'srgb',
    });
  });

  test('supports HEIF, bounded long edge, and semantic quality', () {
    final options = PhotoExportOptions(
      format: PhotoExportFormat.heif,
      size: PhotoExportSize.longEdge,
      longEdgePixels: 2048,
      quality: PhotoExportQuality.standard,
    );

    expect(options.toPlatformArguments(), {
      'format': 'heif',
      'size': 'longEdge',
      'longEdgePixels': 2048,
      'quality': 'standard',
      'colorSpace': 'srgb',
    });
  });

  test('long-edge export requires a safe pixel count', () {
    expect(
      () => PhotoExportOptions(
        size: PhotoExportSize.longEdge,
        longEdgePixels: 100,
      ),
      throwsRangeError,
    );
  });
}
