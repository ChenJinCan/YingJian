// THROWAWAY PROTOTYPE.
// Three mobile-first variants of the complete MVP editing flow.
// State is intentionally in memory and all image processing is simulated.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum PrototypeVariant { resultFirst, groupFirst, guided }

enum PrototypeScope { group, currentPhoto }

enum PrototypeExportStatus { waiting, processing, success, failed }

@immutable
class PrototypePhoto {
  const PrototypePhoto({
    required this.id,
    required this.name,
    required this.url,
  });

  final String id;
  final String name;
  final String url;
}

@immutable
class PrototypeRecipe {
  const PrototypeRecipe({
    required this.id,
    required this.name,
    required this.reason,
    required this.detail,
  });

  final String id;
  final String name;
  final String reason;
  final String detail;
}

const prototypePhotos = [
  PrototypePhoto(
    id: 'p1',
    name: '海边逆光',
    url:
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=1200&q=82',
  ),
  PrototypePhoto(
    id: 'p2',
    name: '咖啡店',
    url:
        'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1200&q=82',
  ),
  PrototypePhoto(
    id: 'p3',
    name: '重点人像',
    url:
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=1200&q=82',
  ),
  PrototypePhoto(
    id: 'p4',
    name: '街角合影',
    url:
        'https://images.unsplash.com/photo-1529139574466-a303027c1d8b?auto=format&fit=crop&w=1200&q=82',
  ),
  PrototypePhoto(
    id: 'p5',
    name: '山间远景',
    url:
        'https://images.unsplash.com/photo-1470770841072-f978cf4d019e?auto=format&fit=crop&w=1200&q=82',
  ),
  PrototypePhoto(
    id: 'p6',
    name: '傍晚散步',
    url:
        'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=82',
  ),
];

const prototypeRecipes = [
  PrototypeRecipe(
    id: 'natural',
    name: '清透自然',
    reason: '提亮人物，保留真实肤色',
    detail: '适合人像与白天组图',
  ),
  PrototypeRecipe(
    id: 'amber',
    name: '暖日氛围',
    reason: '统一冷暖，让傍晚更柔和',
    detail: '适合旅行与生活记录',
  ),
  PrototypeRecipe(
    id: 'film',
    name: '克制胶片',
    reason: '压低饱和，强化层次与质感',
    detail: '适合街景与情绪照片',
  ),
];

class PrototypeSession extends ChangeNotifier {
  PrototypeSession() : variant = _initialVariant();

  PrototypeVariant variant;
  int projectSize = 6;
  int selectedPhotoIndex = 0;
  String? selectedRecipeId;
  PrototypeScope scope = PrototypeScope.group;
  double groupStrength = 0.68;
  double currentExposure = 0;
  bool analysisFallback = false;
  bool showOriginal = false;
  bool simulateExportFailure = true;
  final Map<String, double> photoOverrides = {};
  List<PrototypeExportStatus> exportStatuses = List.filled(
    prototypePhotos.length,
    PrototypeExportStatus.waiting,
  );

  static PrototypeVariant _initialVariant() {
    const value = String.fromEnvironment(
      'YINGJIAN_PROTOTYPE_VARIANT',
      defaultValue: 'A',
    );
    return switch (value.toUpperCase()) {
      'B' => PrototypeVariant.groupFirst,
      'C' => PrototypeVariant.guided,
      _ => PrototypeVariant.resultFirst,
    };
  }

  String get variantKey => switch (variant) {
    PrototypeVariant.resultFirst => 'A',
    PrototypeVariant.groupFirst => 'B',
    PrototypeVariant.guided => 'C',
  };

  String get variantName => switch (variant) {
    PrototypeVariant.resultFirst => '结果优先',
    PrototypeVariant.groupFirst => '组图优先',
    PrototypeVariant.guided => '引导优先',
  };

  PrototypePhoto get selectedPhoto => prototypePhotos[selectedPhotoIndex];

  PrototypeRecipe? get selectedRecipe => selectedRecipeId == null
      ? null
      : prototypeRecipes.firstWhere((recipe) => recipe.id == selectedRecipeId);

  void cycleVariant(int delta) {
    const values = PrototypeVariant.values;
    variant = values[(variant.index + delta + values.length) % values.length];
    notifyListeners();
  }

  void startProject(int size) {
    projectSize = size;
    selectedPhotoIndex = 0;
    selectedRecipeId = null;
    scope = size == 1 ? PrototypeScope.currentPhoto : PrototypeScope.group;
    groupStrength = 0.68;
    currentExposure = 0;
    analysisFallback = false;
    showOriginal = false;
    simulateExportFailure = true;
    photoOverrides.clear();
    exportStatuses = List.filled(
      prototypePhotos.length,
      PrototypeExportStatus.waiting,
    );
    notifyListeners();
  }

  void toggleProjectSize() {
    startProject(projectSize == 1 ? 6 : 1);
  }

  void selectPhoto(int index) {
    selectedPhotoIndex = index.clamp(0, projectSize - 1);
    currentExposure = photoOverrides[selectedPhoto.id] ?? 0;
    notifyListeners();
  }

  void chooseRecipe(String recipeId) {
    selectedRecipeId = recipeId;
    notifyListeners();
  }

  void useFallback() {
    analysisFallback = true;
    selectedRecipeId = 'natural';
    notifyListeners();
  }

  void setScope(PrototypeScope value) {
    scope = projectSize == 1 ? PrototypeScope.currentPhoto : value;
    notifyListeners();
  }

  void setGroupStrength(double value) {
    groupStrength = value;
    notifyListeners();
  }

  void setCurrentExposure(double value) {
    currentExposure = value;
    photoOverrides[selectedPhoto.id] = value;
    notifyListeners();
  }

  void setShowOriginal(bool value) {
    showOriginal = value;
    notifyListeners();
  }

  void prepareExport() {
    exportStatuses = List.filled(
      prototypePhotos.length,
      PrototypeExportStatus.waiting,
    );
    notifyListeners();
  }

  void setExportStatus(int index, PrototypeExportStatus status) {
    exportStatuses[index] = status;
    notifyListeners();
  }

  void retryFailedExports() {
    for (var index = 0; index < projectSize; index += 1) {
      if (exportStatuses[index] == PrototypeExportStatus.failed) {
        exportStatuses[index] = PrototypeExportStatus.success;
      }
    }
    notifyListeners();
  }

  void toggleExportFailure(bool value) {
    simulateExportFailure = value;
    notifyListeners();
  }

  String prettyState() {
    final state = <String, Object?>{
      'variant': '$variantKey - $variantName',
      'projectSize': projectSize,
      'selectedPhoto': '${selectedPhotoIndex + 1} - ${selectedPhoto.name}',
      'selectedRecipe': selectedRecipeId,
      'scope': scope.name,
      'groupStrength': groupStrength,
      'currentExposure': currentExposure,
      'analysisFallback': analysisFallback,
      'showOriginal': showOriginal,
      'photoOverrides': photoOverrides,
      'simulateExportFailure': simulateExportFailure,
      'exportStatuses': exportStatuses
          .take(projectSize)
          .map((status) => status.name)
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(state);
  }
}

class MvpFlowPrototypeApp extends StatefulWidget {
  const MvpFlowPrototypeApp({super.key});

  @override
  State<MvpFlowPrototypeApp> createState() => _MvpFlowPrototypeAppState();
}

class _MvpFlowPrototypeAppState extends State<MvpFlowPrototypeApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _session = PrototypeSession();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF315C49);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: '映见移动端原型',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF4F1E9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F1E9),
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: PrototypeSelectionPage(session: _session),
    );
  }
}

class PrototypeVariantSwitcher extends StatelessWidget {
  const PrototypeVariantSwitcher({
    required this.session,
    required this.onShowState,
    super.key,
  });

  final PrototypeSession session;
  final VoidCallback onShowState;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      top: MediaQuery.paddingOf(context).top + 64,
      child: Material(
        color: const Color(0xF2131814),
        elevation: 12,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 48,
          height: 132,
          child: Column(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: '查看原型状态',
                  child: InkWell(
                    key: const ValueKey('prototype-show-state'),
                    onTap: onShowState,
                    child: Center(
                      child: Text(
                        session.variantKey,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFF4A504B)),
              IconButton(
                key: const ValueKey('prototype-next-variant'),
                onPressed: () => session.cycleVariant(1),
                color: Colors.white,
                icon: const Icon(Icons.swap_vert, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypeHomePage extends StatelessWidget {
  const PrototypeHomePage({
    required this.session,
    required this.onShowState,
    super.key,
  });

  final PrototypeSession session;
  final VoidCallback onShowState;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final home = switch (session.variant) {
          PrototypeVariant.resultFirst => _ResultFirstHome(session: session),
          PrototypeVariant.groupFirst => _GroupFirstHome(session: session),
          PrototypeVariant.guided => _GuidedHome(session: session),
        };
        return Stack(
          children: [
            Positioned.fill(child: home),
            if (kDebugMode)
              PrototypeVariantSwitcher(
                session: session,
                onShowState: onShowState,
              ),
          ],
        );
      },
    );
  }
}

class _ResultFirstHome extends StatelessWidget {
  const _ResultFirstHome({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
        children: [
          const PrototypeTopBar(trailing: '本地处理 · 无需登录'),
          const SizedBox(height: 34),
          const PrototypeEyebrow('智能修图与照片编辑'),
          const PrototypeHeadline('一张精修，\n整组好看。'),
          const SizedBox(height: 14),
          const Text(
            '先给你三个靠谱方向，再把最重要的一张认真修好。',
            style: TextStyle(color: Color(0xFF657168), height: 1.6),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 310,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -0.09,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PrototypePhotoCard(
                      photo: prototypePhotos[0],
                      width: 180,
                      height: 250,
                    ),
                  ),
                ),
                Transform.rotate(
                  angle: 0.09,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PrototypePhotoCard(
                      photo: prototypePhotos[2],
                      width: 180,
                      height: 250,
                    ),
                  ),
                ),
                PrototypePhotoCard(
                  photo: prototypePhotos[1],
                  width: 205,
                  height: 290,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: const ValueKey('prototype-start-group'),
            onPressed: () => _openSelection(context, session, 6),
            child: const Text('开始整理 6 张照片'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            key: const ValueKey('prototype-start-single'),
            onPressed: () => _openSelection(context, session, 1),
            child: const Text('只修一张'),
          ),
        ],
      ),
    );
  }
}

class _GroupFirstHome extends StatelessWidget {
  const _GroupFirstHome({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      child: CustomScrollView(
        slivers: [
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
            sliver: SliverToBoxAdapter(
              child: PrototypeTopBar(trailing: '组图工作台'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemCount: 6,
              itemBuilder: (context, index) {
                return PrototypePhotoCard(photo: prototypePhotos[index]);
              },
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 110),
            sliver: SliverToBoxAdapter(
              child: Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PrototypeEyebrow('组图工作台'),
                      Text(
                        '先看完整一组，\n再决定怎么修。',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      const Text('六张一起建立风格，重点照片仍可单独精修。'),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const ValueKey('prototype-start-group'),
                        onPressed: () => _openSelection(context, session, 6),
                        child: const Text('建立六张项目'),
                      ),
                      TextButton(
                        key: const ValueKey('prototype-start-single'),
                        onPressed: () => _openSelection(context, session, 1),
                        child: const Text('只修一张'),
                      ),
                    ],
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

class _GuidedHome extends StatelessWidget {
  const _GuidedHome({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      backgroundColor: const Color(0xFF173B2D),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 105),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PrototypeTopBar(trailing: '一次只做一个决定', dark: true),
              const Spacer(),
              const PrototypeEyebrow('第一问', dark: true),
              const Text(
                '这次，你想修\n一张还是一组？',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '无论从哪里开始，都会先看到三个本地结果，再决定是否细调。',
                style: TextStyle(color: Color(0xFFB9C9BE), height: 1.6),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    for (var index = 0; index < 3; index += 1)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                          child: PrototypePhotoCard(
                            photo: prototypePhotos[index],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              FilledButton(
                key: const ValueKey('prototype-start-group'),
                style: FilledButton.styleFrom(
                  foregroundColor: const Color(0xFF173B2D),
                  backgroundColor: const Color(0xFFDDEC89),
                ),
                onPressed: () => _openSelection(context, session, 6),
                child: const Text('整理一组'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: const ValueKey('prototype-start-single'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => _openSelection(context, session, 1),
                child: const Text('只修一张'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

void _openSelection(BuildContext context, PrototypeSession session, int size) {
  session.startProject(size);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrototypeSelectionPage(session: session),
    ),
  );
}

class PrototypeSelectionPage extends StatelessWidget {
  const PrototypeSelectionPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return PrototypePageScaffold(
          appBar: AppBar(
            title: const Text('照片'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '本地处理',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF315C49),
                    ),
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFFDF7),
                border: Border(top: BorderSide(color: Color(0xFFE1E4DE))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('prototype-toggle-count'),
                      onPressed: session.toggleProjectSize,
                      child: Text(session.projectSize == 1 ? '单张' : '整组 · 6'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      key: const ValueKey('prototype-analyze'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                PrototypeAnalysisPage(session: session),
                          ),
                        );
                      },
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(session.projectSize == 1 ? '分析这张' : '分析 6 张'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.projectSize == 1 ? '选择重点照片' : '最近项目',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const Icon(Icons.lock_outline, size: 16),
                      const SizedBox(width: 5),
                      Text(
                        '不上传原图',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    key: const ValueKey('prototype-selection-grid'),
                    padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 2,
                          mainAxisSpacing: 2,
                          childAspectRatio: 1,
                        ),
                    itemCount: prototypePhotos.length,
                    itemBuilder: (context, index) {
                      final selected = index < session.projectSize;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          PrototypePhotoCard(
                            photo: prototypePhotos[index],
                            radius: 0,
                          ),
                          if (selected)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: CircleAvatar(
                                radius: 13,
                                backgroundColor: const Color(0xFF315C49),
                                foregroundColor: Colors.white,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PrototypeAnalysisPage extends StatefulWidget {
  const PrototypeAnalysisPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  State<PrototypeAnalysisPage> createState() => _PrototypeAnalysisPageState();
}

class _PrototypeAnalysisPageState extends State<PrototypeAnalysisPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1300), _finish);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish() {
    if (!mounted) {
      return;
    }
    widget.session.chooseRecipe('natural');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PrototypeRecommendationPage(session: widget.session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      appBar: AppBar(title: const Text('本地分析')),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                width: 230,
                height: 310,
                child: PrototypePhotoCard(photo: widget.session.selectedPhoto),
              ),
              const SizedBox(height: 28),
              const LinearProgressIndicator(value: 0.72),
              const SizedBox(height: 18),
              Text(
                '正在统一光线、主体和肤色基线…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text('照片不会上传，也不会消耗云端权益。', textAlign: TextAlign.center),
              const SizedBox(height: 18),
              OutlinedButton(
                key: const ValueKey('prototype-analysis-fallback'),
                onPressed: () {
                  _timer?.cancel();
                  widget.session.useFallback();
                  _finish();
                },
                child: const Text('模拟失败并使用安全方案'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypeRecommendationPage extends StatelessWidget {
  const PrototypeRecommendationPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return switch (session.variant) {
          PrototypeVariant.resultFirst => _ResultFirstRecommendations(
            session: session,
          ),
          PrototypeVariant.groupFirst => _GroupFirstRecommendations(
            session: session,
          ),
          PrototypeVariant.guided => _GuidedRecommendations(session: session),
        };
      },
    );
  }
}

class _ResultFirstRecommendations extends StatelessWidget {
  const _ResultFirstRecommendations({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    final initialPage = prototypeRecipes.indexWhere(
      (recipe) => recipe.id == session.selectedRecipeId,
    );
    return PrototypePageScaffold(
      backgroundColor: const Color(0xFF0E110F),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0E110F),
        title: const Text('选择风格'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '本地预览',
                style: TextStyle(color: Color(0xFFAAB4AD), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                key: const ValueKey('prototype-recipe-page-view'),
                controller: PageController(
                  initialPage: initialPage < 0 ? 0 : initialPage,
                ),
                onPageChanged: (index) =>
                    session.chooseRecipe(prototypeRecipes[index].id),
                itemCount: prototypeRecipes.length,
                itemBuilder: (context, index) {
                  final recipe = prototypeRecipes[index];
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      PrototypePhotoCard(
                        photo: session.selectedPhoto,
                        recipeId: recipe.id,
                        radius: 0,
                      ),
                      const Positioned(
                        left: 16,
                        bottom: 16,
                        child: PrototypeBadge(text: '左右滑动比较', dark: true),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(
              color: const Color(0xFF0E110F),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      for (final recipe in prototypeRecipes)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              key: ValueKey('prototype-recipe-${recipe.id}'),
                              onTap: () => session.chooseRecipe(recipe.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Column(
                                children: [
                                  Container(
                                    height: 54,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color:
                                            session.selectedRecipeId ==
                                                recipe.id
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(2),
                                    child: PrototypePhotoCard(
                                      photo: session.selectedPhoto,
                                      recipeId: recipe.id,
                                      radius: 9,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    recipe.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          session.selectedRecipeId == recipe.id
                                          ? Colors.white
                                          : const Color(0xFFAAB4AD),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const ValueKey('prototype-enter-editor'),
                    onPressed: () => _openEditor(context, session),
                    child: Text(session.projectSize == 1 ? '使用并精修' : '应用到整组'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupFirstRecommendations extends StatelessWidget {
  const _GroupFirstRecommendations({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      appBar: AppBar(title: const Text('选择整组方向')),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView.separated(
                key: const ValueKey('prototype-recipe-list'),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                itemCount: prototypeRecipes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final recipe = prototypeRecipes[index];
                  return PrototypeGroupRecipeTile(
                    recipe: recipe,
                    selected: session.selectedRecipeId == recipe.id,
                    onTap: () => session.chooseRecipe(recipe.id),
                  );
                },
              ),
            ),
            PrototypeRecommendationFooter(session: session),
          ],
        ),
      ),
    );
  }
}

class _GuidedRecommendations extends StatelessWidget {
  const _GuidedRecommendations({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return PrototypePageScaffold(
      backgroundColor: const Color(0xFF173B2D),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF173B2D),
        title: const Text('第二问'),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          children: [
            const Text(
              '哪个方向\n更像你？',
              style: TextStyle(
                color: Colors.white,
                fontSize: 40,
                height: 1.08,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '三个方向都在本地预览，选择之后仍可以调淡和撤销。',
              style: TextStyle(color: Color(0xFFB9C9BE), height: 1.6),
            ),
            const SizedBox(height: 20),
            for (final recipe in prototypeRecipes) ...[
              PrototypeGuidedRecipeTile(
                recipe: recipe,
                selected: session.selectedRecipeId == recipe.id,
                onTap: () => session.chooseRecipe(recipe.id),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('prototype-enter-editor'),
              style: FilledButton.styleFrom(
                foregroundColor: const Color(0xFF173B2D),
                backgroundColor: const Color(0xFFDDEC89),
              ),
              onPressed: session.selectedRecipeId == null
                  ? null
                  : () => _openEditor(context, session),
              child: const Text('选好了，继续'),
            ),
          ],
        ),
      ),
    );
  }
}

class PrototypeRecommendationFooter extends StatelessWidget {
  const PrototypeRecommendationFooter({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '全部由本地配方预览 · 云端生成 0 次',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF657168)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('prototype-enter-editor'),
            onPressed: session.selectedRecipeId == null
                ? null
                : () => _openEditor(context, session),
            child: Text(session.projectSize == 1 ? '用这个方向精修' : '用这个方向编辑整组'),
          ),
        ],
      ),
    );
  }
}

void _openEditor(BuildContext context, PrototypeSession session) {
  session.setScope(
    session.projectSize == 1
        ? PrototypeScope.currentPhoto
        : PrototypeScope.group,
  );
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PrototypeEditorPage(session: session),
    ),
  );
}

class PrototypeEditorPage extends StatelessWidget {
  const PrototypeEditorPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return PrototypePageScaffold(
          appBar: AppBar(
            title: Text(
              '${session.selectedPhotoIndex + 1} / ${session.projectSize} · ${session.selectedPhoto.name}',
            ),
            actions: [
              IconButton(
                key: const ValueKey('prototype-export'),
                tooltip: '检查并导出',
                onPressed: () => _showExportConfirmation(context, session),
                icon: const Icon(Icons.ios_share_outlined),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: switch (session.variant) {
              PrototypeVariant.resultFirst => _ResultFirstEditor(
                session: session,
              ),
              PrototypeVariant.groupFirst => _GroupFirstEditor(
                session: session,
              ),
              PrototypeVariant.guided => _GuidedEditor(session: session),
            },
          ),
        );
      },
    );
  }
}

class _ResultFirstEditor extends StatelessWidget {
  const _ResultFirstEditor({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: LayoutBuilder(
              builder: (context, constraints) => PrototypeInteractivePreview(
                session: session,
                height: constraints.maxHeight,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: PrototypeFilmstrip(session: session),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFDF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 16,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: PrototypeEditPanel(session: session, compact: true),
        ),
      ],
    );
  }
}

class _GroupFirstEditor extends StatelessWidget {
  const _GroupFirstEditor({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            key: const ValueKey('prototype-editor-grid'),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemCount: session.projectSize,
            itemBuilder: (context, index) {
              return PrototypeSelectablePhoto(session: session, index: index);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFFFDF7),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: PrototypeEditPanel(session: session, compact: true),
        ),
      ],
    );
  }
}

class _GuidedEditor extends StatelessWidget {
  const _GuidedEditor({required this.session});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    final isGroup = session.scope == PrototypeScope.group;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        const PrototypeEyebrow('第三问'),
        Text(
          isGroup ? '整组感觉\n合适吗？' : '只把这张\n修好。',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          isGroup ? '先调整共同风格；每张曝光和白平衡仍会独立补偿。' : '当前提亮只写入这张照片，返回后仍停在原来的组内位置。',
          style: const TextStyle(color: Color(0xFF657168), height: 1.55),
        ),
        const SizedBox(height: 18),
        PrototypeInteractivePreview(session: session, height: 390),
        const SizedBox(height: 12),
        PrototypeFilmstrip(session: session),
        const SizedBox(height: 14),
        PrototypeEditPanel(session: session),
      ],
    );
  }
}

class PrototypeEditPanel extends StatelessWidget {
  const PrototypeEditPanel({
    required this.session,
    this.compact = false,
    super.key,
  });

  final PrototypeSession session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isGroup = session.scope == PrototypeScope.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (session.projectSize > 1)
          SegmentedButton<PrototypeScope>(
            key: const ValueKey('prototype-scope-selector'),
            segments: const [
              ButtonSegment(
                value: PrototypeScope.group,
                label: Text('整组'),
                icon: Icon(Icons.collections_outlined),
              ),
              ButtonSegment(
                value: PrototypeScope.currentPhoto,
                label: Text('当前照片'),
                icon: Icon(Icons.photo_outlined),
              ),
            ],
            selected: {session.scope},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                session.setScope(selection.first),
          ),
        if (session.projectSize > 1) const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                isGroup ? '整组强度' : '当前提亮',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              isGroup
                  ? '${(session.groupStrength * 100).round()}%'
                  : '${session.currentExposure >= 0 ? '+' : ''}${session.currentExposure.round()}',
            ),
          ],
        ),
        Slider(
          key: ValueKey(
            isGroup ? 'prototype-group-slider' : 'prototype-single-slider',
          ),
          value: isGroup ? session.groupStrength : session.currentExposure,
          min: isGroup ? 0 : -30,
          max: isGroup ? 1 : 30,
          onChanged: isGroup
              ? session.setGroupStrength
              : session.setCurrentExposure,
        ),
        Text(
          isGroup
              ? '共享风格，但每张仍有独立曝光和白平衡补偿。'
              : '仅保存到 ${session.selectedPhotoIndex + 1}. ${session.selectedPhoto.name}。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF657168)),
        ),
        const SizedBox(height: 12),
        if (isGroup)
          FilledButton(
            key: const ValueKey('prototype-refine-current'),
            onPressed: () => session.setScope(PrototypeScope.currentPhoto),
            child: const Text('精修当前照片'),
          )
        else
          FilledButton(
            key: const ValueKey('prototype-return-group'),
            onPressed: session.projectSize == 1
                ? () => _showExportConfirmation(context, session)
                : () {
                    session.setScope(PrototypeScope.group);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('单张修改已保留，已返回整组')),
                    );
                  },
            child: Text(session.projectSize == 1 ? '完成并检查导出' : '完成单张并返回整组'),
          ),
        if (!compact) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('prototype-open-export'),
            onPressed: () => _showExportConfirmation(context, session),
            icon: const Icon(Icons.ios_share_outlined),
            label: Text('检查并导出 ${session.projectSize} 张'),
          ),
        ],
      ],
    );
  }
}

class PrototypeInteractivePreview extends StatelessWidget {
  const PrototypeInteractivePreview({
    required this.session,
    required this.height,
    super.key,
  });

  final PrototypeSession session;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '当前照片，长按查看原图',
      image: true,
      child: GestureDetector(
        key: const ValueKey('prototype-long-press-preview'),
        onLongPressStart: (_) => session.setShowOriginal(true),
        onLongPressEnd: (_) => session.setShowOriginal(false),
        child: Stack(
          children: [
            PrototypePhotoCard(
              photo: session.selectedPhoto,
              recipeId: session.showOriginal ? null : session.selectedRecipeId,
              width: double.infinity,
              height: height,
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: PrototypeBadge(
                text: session.showOriginal ? '原图' : '长按看原图',
                dark: true,
              ),
            ),
            if (session.photoOverrides.containsKey(session.selectedPhoto.id))
              const Positioned(
                right: 12,
                top: 12,
                child: PrototypeBadge(text: '单张已调'),
              ),
          ],
        ),
      ),
    );
  }
}

class PrototypeFilmstrip extends StatelessWidget {
  const PrototypeFilmstrip({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        key: const ValueKey('prototype-filmstrip'),
        scrollDirection: Axis.horizontal,
        itemCount: session.projectSize,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 58,
            child: PrototypeSelectablePhoto(session: session, index: index),
          );
        },
      ),
    );
  }
}

class PrototypeSelectablePhoto extends StatelessWidget {
  const PrototypeSelectablePhoto({
    required this.session,
    required this.index,
    super.key,
  });

  final PrototypeSession session;
  final int index;

  @override
  Widget build(BuildContext context) {
    final photo = prototypePhotos[index];
    final selected = session.selectedPhotoIndex == index;
    final overridden = session.photoOverrides.containsKey(photo.id);
    return Semantics(
      button: true,
      selected: selected,
      label: '${index + 1}. ${photo.name}${overridden ? '，单张已调' : ''}',
      child: InkWell(
        key: ValueKey('prototype-photo-$index'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => session.selectPhoto(index),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF315C49)
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              padding: const EdgeInsets.all(3),
              child: PrototypePhotoCard(
                photo: photo,
                recipeId: session.selectedRecipeId,
              ),
            ),
            if (overridden)
              const Positioned(
                right: 5,
                top: 5,
                child: PrototypeBadge(text: '单张'),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showExportConfirmation(
  BuildContext context,
  PrototypeSession session,
) async {
  session.prepareExport();
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: session,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '确认导出 ${session.projectSize} 张',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text('JPEG · sRGB · 原像素尺寸高质量导出 · 系统相册'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PrototypeBadge(text: '${session.projectSize} 张'),
                    const PrototypeBadge(text: '本地处理'),
                    const PrototypeBadge(text: '单张失败不回滚'),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  key: const ValueKey('prototype-export-failure-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('模拟第 5 张保存失败'),
                  subtitle: const Text('用于验证部分成功与单项重试'),
                  value: session.simulateExportFailure,
                  onChanged: session.projectSize > 4
                      ? session.toggleExportFailure
                      : null,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('prototype-start-export'),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PrototypeExportPage(session: session),
                      ),
                    );
                  },
                  child: const Text('开始批量导出'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class PrototypeExportPage extends StatefulWidget {
  const PrototypeExportPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  State<PrototypeExportPage> createState() => _PrototypeExportPageState();
}

class _PrototypeExportPageState extends State<PrototypeExportPage> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    final session = widget.session;
    if (_index > 0 &&
        session.exportStatuses[_index - 1] ==
            PrototypeExportStatus.processing) {
      session.setExportStatus(_index - 1, PrototypeExportStatus.success);
    }
    if (_index < session.projectSize) {
      session.setExportStatus(_index, PrototypeExportStatus.processing);
      _index += 1;
      return;
    }
    _timer?.cancel();
    if (session.exportStatuses[session.projectSize - 1] ==
        PrototypeExportStatus.processing) {
      session.setExportStatus(
        session.projectSize - 1,
        PrototypeExportStatus.success,
      );
    }
    if (session.simulateExportFailure && session.projectSize > 4) {
      session.setExportStatus(4, PrototypeExportStatus.failed);
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PrototypeExportResultPage(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        final complete = widget.session.exportStatuses
            .take(widget.session.projectSize)
            .where(
              (status) =>
                  status == PrototypeExportStatus.success ||
                  status == PrototypeExportStatus.failed,
            )
            .length;
        return PrototypePageScaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('正在导出'),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
              children: [
                Text(
                  '正在逐张保存，\n已完成的不回滚。',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: complete / widget.session.projectSize,
                ),
                const SizedBox(height: 18),
                PrototypeExportList(session: widget.session),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PrototypeExportResultPage extends StatelessWidget {
  const PrototypeExportResultPage({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final failed = session.exportStatuses
            .take(session.projectSize)
            .where((status) => status == PrototypeExportStatus.failed)
            .length;
        return PrototypePageScaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('导出结果'),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              children: [
                const PrototypeEyebrow('明确结果，不隐藏失败'),
                Text(
                  failed == 0
                      ? '${session.projectSize} 张都已保存。'
                      : '${session.projectSize - failed} 张已保存，\n$failed 张待重试。',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text('成功结果已写入系统相册，不会因其他照片失败而撤销。'),
                const SizedBox(height: 20),
                PrototypeExportList(session: session),
                const SizedBox(height: 16),
                if (failed > 0)
                  FilledButton(
                    key: const ValueKey('prototype-retry-export'),
                    onPressed: session.retryFailedExports,
                    child: const Text('只重试失败项'),
                  )
                else
                  FilledButton.icon(
                    key: const ValueKey('prototype-share'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('原型：这里将打开系统分享')),
                      );
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('系统分享'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('prototype-finish'),
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                  child: const Text('返回原型首页'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PrototypeExportList extends StatelessWidget {
  const PrototypeExportList({required this.session, super.key});

  final PrototypeSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < session.projectSize; index += 1)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox.square(
              dimension: 46,
              child: PrototypePhotoCard(photo: prototypePhotos[index]),
            ),
            title: Text('${index + 1}. ${prototypePhotos[index].name}'),
            subtitle:
                session.photoOverrides.containsKey(prototypePhotos[index].id)
                ? const Text('单张已调')
                : null,
            trailing: PrototypeStatusBadge(
              status: session.exportStatuses[index],
            ),
          ),
      ],
    );
  }
}

class PrototypeRecipeCard extends StatelessWidget {
  const PrototypeRecipeCard({
    required this.recipe,
    required this.photo,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final PrototypeRecipe recipe;
  final PrototypePhoto photo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${recipe.name}，${recipe.reason}',
      child: InkWell(
        key: ValueKey('prototype-recipe-${recipe.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: selected ? 5 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(
              color: selected ? const Color(0xFF315C49) : Colors.transparent,
              width: 3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PrototypePhotoCard(
                  photo: photo,
                  recipeId: recipe.id,
                  radius: 0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PrototypeBadge(text: recipe.id == 'natural' ? '推荐' : '备选'),
                    const SizedBox(height: 8),
                    Text(
                      recipe.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(recipe.reason),
                    const SizedBox(height: 3),
                    Text(
                      recipe.detail,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypeGroupRecipeTile extends StatelessWidget {
  const PrototypeGroupRecipeTile({
    required this.recipe,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final PrototypeRecipe recipe;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('prototype-recipe-${recipe.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF315C49)
                  : const Color(0xFFD8DDD6),
              width: selected ? 3 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: 4,
                  itemBuilder: (context, index) => PrototypePhotoCard(
                    photo: prototypePhotos[index],
                    recipeId: recipe.id,
                    radius: 6,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(recipe.reason),
                    const SizedBox(height: 8),
                    PrototypeBadge(text: recipe.id == 'natural' ? '推荐' : '备选'),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypeGuidedRecipeTile extends StatelessWidget {
  const PrototypeGuidedRecipeTile({
    required this.recipe,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final PrototypeRecipe recipe;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('prototype-recipe-${recipe.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? const Color(0xFFDDEC89) : Colors.transparent,
              width: 3,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 86,
                child: PrototypePhotoCard(
                  photo: prototypePhotos[2],
                  recipeId: recipe.id,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recipe.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(recipe.reason),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle : Icons.arrow_forward),
            ],
          ),
        ),
      ),
    );
  }
}

class PrototypePhotoCard extends StatelessWidget {
  const PrototypePhotoCard({
    required this.photo,
    this.recipeId,
    this.width,
    this.height,
    this.radius = 16,
    super.key,
  });

  final PrototypePhoto photo;
  final String? recipeId;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final image = Image.network(
      photo.url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          return child;
        }
        return const ColoredBox(
          color: Color(0xFFD8DDD6),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFFD8DDD6),
        child: Center(child: Icon(Icons.photo_outlined, size: 36)),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: recipeId == null
            ? image
            : ColorFiltered(
                colorFilter: ColorFilter.matrix(_recipeMatrix(recipeId!)),
                child: image,
              ),
      ),
    );
  }
}

List<double> _recipeMatrix(String id) {
  return switch (id) {
    'amber' => const [
      1.12,
      0.04,
      0,
      0,
      5,
      0.02,
      1.03,
      0,
      0,
      2,
      0,
      0,
      0.9,
      0,
      -2,
      0,
      0,
      0,
      1,
      0,
    ],
    'film' => const [
      0.82,
      0.08,
      0.08,
      0,
      2,
      0.06,
      0.86,
      0.06,
      0,
      1,
      0.05,
      0.07,
      0.78,
      0,
      3,
      0,
      0,
      0,
      1,
      0,
    ],
    _ => const [
      1.04,
      0,
      0,
      0,
      2,
      0,
      1.04,
      0,
      0,
      2,
      0,
      0,
      1.04,
      0,
      2,
      0,
      0,
      0,
      1,
      0,
    ],
  };
}

class PrototypePageScaffold extends StatelessWidget {
  const PrototypePageScaffold({
    required this.child,
    this.appBar,
    this.backgroundColor,
    this.bottomNavigationBar,
    super.key,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      backgroundColor: backgroundColor,
      bottomNavigationBar: bottomNavigationBar,
      body: child,
    );
  }
}

class PrototypeTopBar extends StatelessWidget {
  const PrototypeTopBar({required this.trailing, this.dark = false, super.key});

  final String trailing;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '映见',
          style: TextStyle(
            color: dark ? Colors.white : const Color(0xFF172019),
            fontSize: 23,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: TextStyle(
            color: dark ? const Color(0xFFB9C9BE) : const Color(0xFF657168),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class PrototypeHeadline extends StatelessWidget {
  const PrototypeHeadline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF172019),
        fontSize: 46,
        height: 1.06,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.8,
      ),
    );
  }
}

class PrototypeEyebrow extends StatelessWidget {
  const PrototypeEyebrow(this.text, {this.dark = false, super.key});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: dark ? const Color(0xFFDDEC89) : const Color(0xFF315C49),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class PrototypeBadge extends StatelessWidget {
  const PrototypeBadge({required this.text, this.dark = false, super.key});

  final String text;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xCC172019) : const Color(0xFFDDEC89),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            color: dark ? Colors.white : const Color(0xFF173B2D),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class PrototypeStatusBadge extends StatelessWidget {
  const PrototypeStatusBadge({required this.status, super.key});

  final PrototypeExportStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      PrototypeExportStatus.waiting => ('等待', const Color(0xFFE8ECE8)),
      PrototypeExportStatus.processing => ('处理中', const Color(0xFFDDEAF2)),
      PrototypeExportStatus.success => ('已保存', const Color(0xFFE4EEE7)),
      PrototypeExportStatus.failed => ('失败', const Color(0xFFFAE0DC)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
