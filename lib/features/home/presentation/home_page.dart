import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/l10n.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PhotoProjectStore? _store;
  Future<PhotoProject?>? _latestProject;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<PhotoProjectStore>();
    if (!identical(store, _store)) {
      _store = store;
      _latestProject = store.loadLatest();
    }
  }

  void _reload() {
    final latest = _store!.loadLatest();
    setState(() {
      _latestProject = latest;
    });
  }

  Future<void> _openEditor({bool startWithImport = false}) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.editor, arguments: startWithImport);
    if (mounted) _reload();
  }

  Future<void> _startNew(PhotoProject? project) async {
    if (project == null) {
      await _openEditor(startWithImport: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.startNewProject),
        content: Text(context.l10n.deleteProjectConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.deleteAndStartNew),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final store = _store;
    if (store is! PhotoProjectLifecycleStore) return;
    try {
      await store.deleteProject(project);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.projectDeleteFailed)));
      return;
    }
    if (!mounted) return;
    _reload();
    await _openEditor(startWithImport: true);
  }

  void _showCameraBoundary() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('首版先从相册选择照片；拍摄入口将在相机画质合同完成后开放。')),
    );
  }

  void _showMenu(PhotoProject? project) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: Text(context.l10n.homePrimaryAction),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startNew(project);
                },
              ),
              if (project != null)
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: Text(context.l10n.continueLastEditing),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _openEditor();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(context.l10n.settings),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).pushNamed(AppRoutes.settings);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('home-page'),
      backgroundColor: AppTheme.canvas,
      body: FutureBuilder<PhotoProject?>(
        key: const ValueKey('home-full-screen-background'),
        future: _latestProject,
        builder: (context, snapshot) {
          final project = snapshot.data;
          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                _HomeHeader(
                  onMenu: () => _showMenu(project),
                  onSettings: () =>
                      Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
                      children: [
                        _HeroPhoto(project: project),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const ValueKey('home-start-editing'),
                          onPressed: () => _startNew(project),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                          ),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(context.l10n.homePrimaryAction),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const ValueKey('home-camera'),
                          onPressed: _showCameraBoundary,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            foregroundColor: AppTheme.gold,
                            side: const BorderSide(color: AppTheme.gold),
                          ),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('拍一张'),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          context.l10n.recentProjects,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const LinearProgressIndicator(minHeight: 2)
                        else if (snapshot.hasError)
                          _RestoreFailure(onRetry: _reload)
                        else if (project == null)
                          _EmptyRecent(onStart: () => _startNew(null))
                        else
                          _RecentDraftCard(
                            project: project,
                            onTap: () => _openEditor(),
                          ),
                      ],
                    ),
                  ),
                ),
                NavigationBar(
                  key: const ValueKey('home-navigation'),
                  selectedIndex: 0,
                  onDestinationSelected: (index) {
                    switch (index) {
                      case 1:
                        _startNew(project);
                      case 2:
                        _openEditor(startWithImport: project == null);
                      case 3:
                        Navigator.of(context).pushNamed(AppRoutes.settings);
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_rounded),
                      label: '首页',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.photo_library_outlined),
                      label: '照片',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_fix_high_outlined),
                      label: '编辑',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      label: '我的',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onMenu, required this.onSettings});

  final VoidCallback onMenu;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('home-menu'),
          tooltip: '菜单',
          onPressed: onMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
        Expanded(
          child: Text(
            context.l10n.appTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('home-settings'),
          tooltip: context.l10n.settings,
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
  );
}

class _HeroPhoto extends StatelessWidget {
  const _HeroPhoto({required this.project});

  final PhotoProject? project;

  @override
  Widget build(BuildContext context) {
    final photo = project?.photos.firstOrNull;
    final size = MediaQuery.sizeOf(context);
    final availableWidth = size.width - 40;
    final heightFraction = size.height < 700 ? 0.3 : 0.42;
    final height = math.min(
      availableWidth / 1.06,
      size.height * heightFraction,
    );
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo == null)
              const _EmptyHeroBackdrop()
            else
              Image.file(
                File(photo.localPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _EmptyHeroBackdrop(),
              ),
            if (photo == null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.homeHeroTitle,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.homeTagline,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHeroBackdrop extends StatelessWidget {
  const _EmptyHeroBackdrop();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF4A4436), Color(0xFF262522), Color(0xFF0B0D0E)],
      ),
    ),
    child: Center(
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 64,
        color: AppTheme.gold.withValues(alpha: 0.55),
      ),
    ),
  );
}

class _RecentDraftCard extends StatelessWidget {
  const _RecentDraftCard({required this.project, required this.onTap});

  final PhotoProject project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photo = project.photos.first;
    final local = project.updatedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    return Material(
      color: const Color(0xFF1B1D1E),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-resume-project'),
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 142,
              height: 104,
              child: Image.file(
                File(photo.localPath),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFF252728),
                  child: Icon(Icons.photo_outlined),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.unfinishedProject,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.l10n.lastProjectSummary(
                        project.photos.length,
                        material.formatCompactDate(local),
                        material.formatTimeOfDay(
                          TimeOfDay.fromDateTime(local),
                          alwaysUse24HourFormat: true,
                        ),
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.arrow_forward_ios_rounded, size: 17),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onStart,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(72),
      foregroundColor: AppTheme.muted,
    ),
    icon: const Icon(Icons.photo_outlined),
    label: Text(context.l10n.noRecentProjects),
  );
}

class _RestoreFailure extends StatelessWidget {
  const _RestoreFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(context.l10n.projectRestoreFailed),
    ),
  );
}
