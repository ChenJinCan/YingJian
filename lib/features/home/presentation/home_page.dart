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
  PhotoImporter? _importer;
  Future<List<PhotoProject>>? _projects;
  String? _operationError;
  List<PhotoImportFailure> _importFailures = const [];
  bool _preparingPhoto = false;
  bool _cancelPreparingRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<PhotoProjectStore>();
    _importer = context.read<PhotoImporter>();
    if (!identical(store, _store)) {
      _store = store;
      _projects = _loadProjects(store);
    }
  }

  void _reload() {
    final projects = _loadProjects(_store!);
    setState(() {
      _projects = projects;
    });
  }

  Future<List<PhotoProject>> _loadProjects(PhotoProjectStore store) async {
    if (store is PhotoProjectCatalogStore) {
      final projects = List<PhotoProject>.of(await store.loadProjects());
      projects.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return projects;
    }
    final latest = await store.loadLatest();
    return latest == null ? const [] : [latest];
  }

  Future<void> _openEditor({PhotoProject? project}) async {
    final store = _store;
    if (store is PhotoProjectCatalogStore) {
      if (project != null) {
        await store.activateProject(project.id);
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushNamed(AppRoutes.editor);
    if (mounted) _reload();
  }

  Future<void> _startNew() async {
    if (_preparingPhoto) return;
    final store = _store!;
    final importer = _importer!;
    setState(() {
      _preparingPhoto = true;
      _cancelPreparingRequested = false;
      _operationError = null;
      _importFailures = const [];
    });
    PhotoProjectSession? session;
    try {
      if (store is PhotoProjectCatalogStore) await store.startNewProject();
      session = PhotoProjectSession(importer: importer, store: store);
      final result = await session.importPhotos();
      if (_cancelPreparingRequested) {
        final importedProject = session.project;
        if (importedProject != null && store is PhotoProjectLifecycleStore) {
          await store.deleteProject(importedProject);
        }
        return;
      }
      if (!mounted) return;
      switch (result) {
        case PhotoImportResult.imported:
          setState(() => _preparingPhoto = false);
          await Navigator.of(context).pushNamed(AppRoutes.editor);
          if (mounted) _reload();
        case PhotoImportResult.rejected:
          setState(() => _importFailures = session!.importFailures);
        case PhotoImportResult.canceled:
        case PhotoImportResult.limitReached:
          break;
      }
    } on Object {
      if (mounted && !_cancelPreparingRequested) {
        setState(() => _operationError = context.l10n.photoImportFailed);
      }
    } finally {
      session?.dispose();
      if (mounted) {
        setState(() {
          _preparingPhoto = false;
          _cancelPreparingRequested = false;
        });
      }
    }
  }

  void _cancelPreparing() {
    if (!_preparingPhoto) return;
    setState(() => _cancelPreparingRequested = true);
  }

  Widget _newPhotoAction({required bool hasDrafts}) {
    final hasImportError =
        _operationError != null || _importFailures.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasDrafts)
          OutlinedButton.icon(
            key: hasImportError
                ? const ValueKey('home-import-retry')
                : const ValueKey('home-new-project'),
            onPressed: _preparingPhoto ? null : _startNew,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppTheme.gold,
              side: const BorderSide(color: AppTheme.gold),
            ),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _preparingPhoto
                  ? context.l10n.preparingPhoto
                  : context.l10n.selectNewPhoto,
            ),
          )
        else
          FilledButton.icon(
            key: hasImportError
                ? const ValueKey('home-import-retry')
                : const ValueKey('home-start-editing'),
            onPressed: _preparingPhoto ? null : _startNew,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              _preparingPhoto
                  ? context.l10n.preparingPhoto
                  : context.l10n.homePrimaryAction,
            ),
          ),
        if (_preparingPhoto) ...[
          Semantics(
            key: const ValueKey('home-photo-preparing'),
            liveRegion: true,
            label: context.l10n.preparingPhoto,
            child: const LinearProgressIndicator(minHeight: 2),
          ),
          TextButton(
            key: const ValueKey('home-cancel-import'),
            onPressed: _cancelPreparingRequested ? null : _cancelPreparing,
            child: Text(context.l10n.cancel),
          ),
        ],
      ],
    );
  }

  Future<void> _deleteDraft(PhotoProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteDraft),
        content: Text(context.l10n.draftDeleteConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('home-confirm-delete-draft'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.deleteDraft),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final store = _store;
    if (store is! PhotoProjectLifecycleStore) {
      setState(() => _operationError = context.l10n.projectDeleteFailed);
      return;
    }
    try {
      await store.deleteProject(project);
      if (!mounted) return;
      setState(() => _operationError = null);
      _reload();
    } on Object {
      if (mounted) {
        setState(() => _operationError = context.l10n.projectDeleteFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('home-page'),
      backgroundColor: AppTheme.canvas,
      body: FutureBuilder<List<PhotoProject>>(
        key: const ValueKey('home-full-screen-background'),
        future: _projects,
        builder: (context, snapshot) {
          final projects = snapshot.data ?? const <PhotoProject>[];
          final latestProject = projects.firstOrNull;
          final otherProjects = projects.skip(1).toList(growable: false);
          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                _HomeHeader(
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
                        const _HeroPhoto(project: null),
                        const SizedBox(height: 16),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const LinearProgressIndicator(minHeight: 2)
                        else if (snapshot.hasError)
                          _RestoreFailure(onRetry: _reload)
                        else if (projects.isEmpty)
                          _newPhotoAction(hasDrafts: false)
                        else ...[
                          _RecentDraftCard(
                            key: ValueKey(
                              'home-featured-draft-${latestProject!.id}',
                            ),
                            project: latestProject,
                            isLatest: true,
                            onTap: () => _openEditor(project: latestProject),
                            onDelete: () => _deleteDraft(latestProject),
                          ),
                          const SizedBox(height: 10),
                          _newPhotoAction(hasDrafts: true),
                          if (otherProjects.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              context.l10n.otherDrafts,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                          ],
                          for (
                            var index = 0;
                            index < otherProjects.length;
                            index++
                          )
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == otherProjects.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: _RecentDraftCard(
                                key: ValueKey(
                                  'home-draft-${otherProjects[index].id}',
                                ),
                                project: otherProjects[index],
                                isLatest: false,
                                onTap: () =>
                                    _openEditor(project: otherProjects[index]),
                                onDelete: () =>
                                    _deleteDraft(otherProjects[index]),
                              ),
                            ),
                        ],
                        if (_operationError != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _operationError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                        if (_importFailures.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _HomeImportFailures(failures: _importFailures),
                        ],
                      ],
                    ),
                  ),
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
  const _HomeHeader({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
    child: Row(
      children: [
        const SizedBox(width: 48),
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
  const _RecentDraftCard({
    required this.project,
    required this.isLatest,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final PhotoProject project;
  final bool isLatest;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
                      context.l10n.lastEditedAt(
                        material.formatCompactDate(local),
                        material.formatTimeOfDay(
                          TimeOfDay.fromDateTime(local),
                          alwaysUse24HourFormat: true,
                        ),
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _draftStatusLabel(context, project),
                      key: ValueKey('home-draft-status-${project.id}'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          key: isLatest
                              ? const ValueKey('home-resume-project')
                              : ValueKey('home-continue-draft-${project.id}'),
                          onPressed: onTap,
                          child: Text(context.l10n.continueEditing),
                        ),
                        TextButton(
                          key: ValueKey('home-delete-draft-${project.id}'),
                          onPressed: onDelete,
                          child: Text(context.l10n.deleteDraft),
                        ),
                      ],
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

String _draftStatusLabel(BuildContext context, PhotoProject project) {
  if (project.requiresUpdate) return context.l10n.draftStatusNeedsUpdate;
  final exportedVersion = project.lastSuccessfulExportEditStateVersion;
  if (exportedVersion == null) return context.l10n.draftStatusEditing;
  return exportedVersion == project.editStateVersion
      ? context.l10n.draftStatusExported
      : context.l10n.draftStatusModified;
}

class _RestoreFailure extends StatelessWidget {
  const _RestoreFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.draftStatusNeedsRecovery,
          key: const ValueKey('home-project-needs-recovery'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(context.l10n.projectRestoreFailed),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('home-retry-project-restore'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(context.l10n.retry),
        ),
      ],
    ),
  );
}

class _HomeImportFailures extends StatelessWidget {
  const _HomeImportFailures({required this.failures});

  final List<PhotoImportFailure> failures;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.photoImportIssuesTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final failure in failures)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _homePhotoImportFailureMessage(context, failure),
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _homePhotoImportFailureMessage(
  BuildContext context,
  PhotoImportFailure failure,
) => switch (failure.reason) {
  PhotoImportFailureReason.unsupportedFormat ||
  PhotoImportFailureReason.unsupportedColorSpace =>
    context.l10n.photoUnsupportedFormat(failure.photoName),
  PhotoImportFailureReason.animatedImage =>
    context.l10n.photoAnimatedUnsupported(failure.photoName),
  PhotoImportFailureReason.fileTooLarge => context.l10n.photoFileTooLarge(
    failure.photoName,
  ),
  PhotoImportFailureReason.dimensionsTooLarge =>
    context.l10n.photoDimensionsTooLarge(failure.photoName),
  PhotoImportFailureReason.unreadable => context.l10n.photoUnreadable(
    failure.photoName,
  ),
  PhotoImportFailureReason.copyFailed => context.l10n.photoCopyFailed(
    failure.photoName,
  ),
};
