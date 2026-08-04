// THROWAWAY PROTOTYPE: validates iOS Vision mask alignment, not product UI.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class PortraitMaskSpikeApp extends StatelessWidget {
  const PortraitMaskSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'iOS 人像区域 Spike',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B4D)),
        useMaterial3: true,
      ),
      home: const PortraitMaskSpikePage(),
    );
  }
}

class PortraitMaskSpikePage extends StatefulWidget {
  const PortraitMaskSpikePage({super.key});

  @override
  State<PortraitMaskSpikePage> createState() => _PortraitMaskSpikePageState();
}

class _PortraitMaskSpikePageState extends State<PortraitMaskSpikePage> {
  static const _channel = MethodChannel('yingjian/portrait_mask_spike');
  static const _autoRunFixture = bool.fromEnvironment('PORTRAIT_SPIKE_AUTORUN');

  final _picker = ImagePicker();
  PortraitMaskSpikeResult? _result;
  String? _selectedPath;
  String? _error;
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    if (_autoRunFixture) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _analyzePath('${Directory.systemTemp.path}/portrait-spike-input.png');
      });
    }
  }

  Future<void> _pickAndAnalyze() async {
    final selected = await _picker.pickImage(source: ImageSource.gallery);
    if (selected == null || !mounted) {
      return;
    }
    await _analyzePath(selected.path);
  }

  Future<void> _analyzePath(String sourcePath) async {
    setState(() {
      _selectedPath = sourcePath;
      _result = null;
      _error = null;
      _analyzing = true;
    });
    try {
      final value = await _channel.invokeMethod<Object?>('analyzePortrait', {
        'sourcePath': sourcePath,
      });
      if (value is! Map<Object?, Object?>) {
        throw const FormatException('原生分析返回了无效结果');
      }
      final result = PortraitMaskSpikeResult.fromMap(value);
      if (mounted) {
        setState(() => _result = result);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = '${error.code}：${error.message ?? '分析失败'}');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('iOS 人像区域 Spike')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _PrototypeNotice(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _analyzing ? null : _pickAndAnalyze,
              icon: _analyzing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_library_outlined),
              label: Text(_analyzing ? '正在分析…' : '选择一张人像'),
            ),
            if (_selectedPath != null && result == null) ...[
              const SizedBox(height: 16),
              _DebugImageCard(title: '已选择原图', path: _selectedPath!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              _AnalysisState(result: result),
              const SizedBox(height: 16),
              _DebugImageWrap(result: result),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrototypeNotice extends StatelessWidget {
  const _PrototypeNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THROWAWAY PROTOTYPE',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              '这里只验证 Vision 人脸几何、五官保护区、图片方向和一条受区域约束的像素候选。'
              '绿色区域不是真实皮肤分割，三档结果也不具备生产资格，必须先通过授权样片盲评。',
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisState extends StatelessWidget {
  const _AnalysisState({required this.result});

  final PortraitMaskSpikeResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('完整分析状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              'faceCount: ${result.faceCount}\n'
              'proxy: ${result.width} × ${result.height}\n'
              'source: ${result.sourceWidth} × ${result.sourceHeight}\n'
              'candidateKind: ${result.candidateKind}\n'
              'geometryOnly: ${result.geometryOnly}\n'
              'effectVersion: ${result.effectVersion}\n'
              'strengths: ${result.defaultStrength} / ${result.highSafeStrength}\n'
              'productionEligible: ${result.productionEligible}\n'
              'environment: ${result.executionEnvironment}\n'
              'device copy source: ${result.captureRelativePath}\n'
              'landmarks: ${result.landmarkSummary}\n'
              'bounds: ${result.landmarkBoundsSummary}',
            ),
            if (result.executionEnvironment == 'simulator-cpu-only') ...[
              const SizedBox(height: 8),
              const Text('模拟器仅验证通道和失败降级；五官坐标必须在物理 iPhone 上重新验收。'),
            ],
            if (result.faceCount == 0) ...[
              const SizedBox(height: 8),
              const Text('没有检测到适用人脸；正式产品必须在这里安全降级。'),
            ],
          ],
        ),
      ),
    );
  }
}

class _DebugImageWrap extends StatelessWidget {
  const _DebugImageWrap({required this.result});

  final PortraitMaskSpikeResult result;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width >= 800 ? (width - 64) / 2 : width - 32;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '1. 方向规范化后的原图',
            path: result.sourceProxyPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '2. 几何候选脸部区域',
            path: result.candidateMaskPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '3. 五官保护区域',
            path: result.protectionMaskPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '4. 最终有效区域',
            path: result.effectiveMaskPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '5. 有效区域覆盖检查',
            path: result.overlayPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '6. 方向规范化原像素基线 JPEG',
            path: result.baselineOriginalPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '7. 人像关闭原像素导出',
            path: result.offExportPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '8. 默认强度代理预览',
            path: result.defaultPreviewPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '9. 默认强度原像素导出',
            path: result.defaultExportPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _DebugImageCard(
            title: '10. 高安全强度原像素导出',
            path: result.highSafeExportPath,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                '采集清单：${result.captureManifestPath}\n'
                '设备复制路径：${result.captureRelativePath}',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DebugImageCard extends StatelessWidget {
  const _DebugImageCard({required this.title, required this.path});

  final String title;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
          ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, error, stackTrace) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '调试图片读取失败',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PortraitMaskSpikeResult {
  const PortraitMaskSpikeResult({
    required this.faceCount,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.sourceProxyPath,
    required this.candidateMaskPath,
    required this.protectionMaskPath,
    required this.effectiveMaskPath,
    required this.overlayPath,
    required this.baselineOriginalPath,
    required this.offExportPath,
    required this.defaultExportPath,
    required this.highSafeExportPath,
    required this.defaultPreviewPath,
    required this.captureManifestPath,
    required this.captureRelativePath,
    required this.candidateKind,
    required this.geometryOnly,
    required this.effectVersion,
    required this.defaultStrength,
    required this.highSafeStrength,
    required this.productionEligible,
    required this.executionEnvironment,
    required this.landmarkSummary,
    required this.landmarkBoundsSummary,
  });

  factory PortraitMaskSpikeResult.fromMap(Map<Object?, Object?> value) {
    T read<T>(String key) {
      final item = value[key];
      if (item is! T) {
        throw FormatException('缺少或无效字段：$key');
      }
      return item;
    }

    return PortraitMaskSpikeResult(
      faceCount: read<int>('faceCount'),
      width: read<int>('width'),
      height: read<int>('height'),
      sourceWidth: read<int>('sourceWidth'),
      sourceHeight: read<int>('sourceHeight'),
      sourceProxyPath: read<String>('sourceProxyPath'),
      candidateMaskPath: read<String>('candidateMaskPath'),
      protectionMaskPath: read<String>('protectionMaskPath'),
      effectiveMaskPath: read<String>('effectiveMaskPath'),
      overlayPath: read<String>('overlayPath'),
      baselineOriginalPath: read<String>('baselineOriginalPath'),
      offExportPath: read<String>('offExportPath'),
      defaultExportPath: read<String>('defaultExportPath'),
      highSafeExportPath: read<String>('highSafeExportPath'),
      defaultPreviewPath: read<String>('defaultPreviewPath'),
      captureManifestPath: read<String>('captureManifestPath'),
      captureRelativePath: read<String>('captureRelativePath'),
      candidateKind: read<String>('candidateKind'),
      geometryOnly: read<bool>('geometryOnly'),
      effectVersion: read<String>('effectVersion'),
      defaultStrength: read<double>('defaultStrength'),
      highSafeStrength: read<double>('highSafeStrength'),
      productionEligible: read<bool>('productionEligible'),
      executionEnvironment: read<String>('executionEnvironment'),
      landmarkSummary: read<String>('landmarkSummary'),
      landmarkBoundsSummary: read<String>('landmarkBoundsSummary'),
    );
  }

  final int faceCount;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
  final String sourceProxyPath;
  final String candidateMaskPath;
  final String protectionMaskPath;
  final String effectiveMaskPath;
  final String overlayPath;
  final String baselineOriginalPath;
  final String offExportPath;
  final String defaultExportPath;
  final String highSafeExportPath;
  final String defaultPreviewPath;
  final String captureManifestPath;
  final String captureRelativePath;
  final String candidateKind;
  final bool geometryOnly;
  final String effectVersion;
  final double defaultStrength;
  final double highSafeStrength;
  final bool productionEligible;
  final String executionEnvironment;
  final String landmarkSummary;
  final String landmarkBoundsSummary;
}
