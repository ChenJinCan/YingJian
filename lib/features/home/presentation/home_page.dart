import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/creation/domain/creation_task.dart';
import 'package:yingjian/features/generation/application/generation_coordinator.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/project/domain/photo_project.dart';
import 'package:yingjian/l10n/l10n.dart';
import 'package:yingjian/observability/local_diagnostic_log.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  PhotoProjectStore? _store;
  PhotoImporter? _importer;
  GenerationCoordinator? _generationCoordinator;
  Future<List<PhotoProject>>? _projects;
  String? _importError;
  String? _projectActionError;
  List<PhotoImportFailure> _importFailures = const [];
  CreationTask? _preparingTask;
  CreationTask? _failedTask;
  String? _openingProjectId;
  bool _cancelPreparingRequested = false;
  bool _retryingGenerationCleanups = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = context.read<PhotoProjectStore>();
    _importer = context.read<PhotoImporter>();
    _generationCoordinator = context.read<GenerationCoordinator>();
    if (!identical(store, _store)) {
      _store = store;
      _projects = _loadProjects(store);
    }
  }

  Future<List<PhotoProject>> _loadProjects(PhotoProjectStore store) async {
    if (store is PhotoProjectCatalogStore) {
      final projects = List<PhotoProject>.of(await store.loadProjects());
      projects.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      _retryGenerationCleanups(projects);
      return projects;
    }
    final latest = await store.loadLatest();
    final projects = latest == null ? <PhotoProject>[] : [latest];
    _retryGenerationCleanups(projects);
    return projects;
  }

  void _retryGenerationCleanups(List<PhotoProject> projects) {
    final coordinator = _generationCoordinator;
    if (coordinator == null || _retryingGenerationCleanups) return;
    _retryingGenerationCleanups = true;
    unawaited(
      coordinator
          .retryProjectDeletionCleanups(
            existingProjectIds: projects.map((project) => project.id).toSet(),
          )
          .catchError((_) {
            // A malformed or temporarily unavailable cleanup store retries on
            // a later catalog load and must not block the home page.
          })
          .whenComplete(() => _retryingGenerationCleanups = false),
    );
  }

  void _reload() {
    final store = _store;
    if (store == null || !mounted) return;
    setState(() {
      _projects = _loadProjects(store);
    });
  }

  String _routeFor(CreationTask task) => switch (task) {
    CreationTask.optimize => AppRoutes.optimizeWorkspace,
    CreationTask.style => AppRoutes.applyStyleWorkspace,
    CreationTask.cleanup => AppRoutes.cleanupWorkspace,
    CreationTask.motion => AppRoutes.motionStyleWorkspace,
  };

  Future<void> _openCreation(PhotoProject project) async {
    if (_preparingTask != null || _openingProjectId != null) return;
    final store = _store;
    setState(() {
      _openingProjectId = project.id;
      _projectActionError = null;
    });
    try {
      if (store is PhotoProjectCatalogStore) {
        await store.activateProject(project.id);
      }
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        _routeFor(project.creationTask),
        arguments: CreationRouteArguments(
          projectId: project.id,
          task: project.creationTask,
        ),
      );
    } on Object {
      if (mounted) {
        setState(() => _projectActionError = context.l10n.projectRestoreFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _openingProjectId = null);
        _reload();
      }
    }
  }

  Future<void> _startNew(CreationTask task) async {
    if (_preparingTask != null || _openingProjectId != null) return;
    final store = _store!;
    final importer = _importer!;
    final diagnosticLog = context.read<DiagnosticLog>();
    final timer = Stopwatch()..start();
    diagnosticLog.record(
      DiagnosticLogEvent(
        level: DiagnosticLogLevel.info,
        component: 'home',
        operation: 'start_photo_import',
        result: 'started',
        reason: task.name,
      ),
    );
    setState(() {
      _preparingTask = task;
      _failedTask = null;
      _cancelPreparingRequested = false;
      _importError = null;
      _projectActionError = null;
      _importFailures = const [];
    });
    PhotoProjectSession? session;
    var catalogTransactionStarted = false;
    var importedProjectKept = false;
    try {
      if (store is PhotoProjectCatalogStore) {
        await store.startNewProject();
        catalogTransactionStarted = true;
      }
      session = PhotoProjectSession(
        importer: importer,
        store: store,
        creationIntent: task.creationIntent,
        creationTask: task,
      );
      final result = await session.importPhotos(
        isCanceled: () => _cancelPreparingRequested,
      );
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
          diagnosticLog.record(
            DiagnosticLogEvent(
              level: DiagnosticLogLevel.info,
              component: 'home',
              operation: 'start_photo_import',
              result: 'succeeded',
              reason: task.name,
              itemCount: session.project!.photos.length,
              durationMs: timer.elapsedMilliseconds,
            ),
          );
          final projectId = session.project!.id;
          importedProjectKept = true;
          setState(() => _preparingTask = null);
          await Navigator.of(context).pushNamed(
            _routeFor(task),
            arguments: CreationRouteArguments(projectId: projectId, task: task),
          );
          if (mounted) _reload();
        case PhotoImportResult.rejected:
          diagnosticLog.record(
            DiagnosticLogEvent(
              level: DiagnosticLogLevel.warning,
              component: 'home',
              operation: 'start_photo_import',
              result: 'rejected',
              reason: task.name,
              itemCount: session.importFailures.length,
              durationMs: timer.elapsedMilliseconds,
            ),
          );
          setState(() {
            _failedTask = task;
            _importFailures = session!.importFailures;
          });
        case PhotoImportResult.canceled:
        case PhotoImportResult.limitReached:
          diagnosticLog.record(
            DiagnosticLogEvent(
              level: DiagnosticLogLevel.info,
              component: 'home',
              operation: 'start_photo_import',
              result: result.name,
              reason: task.name,
              durationMs: timer.elapsedMilliseconds,
            ),
          );
          break;
      }
    } on Object catch (error) {
      diagnosticLog.record(
        DiagnosticLogEvent(
          level: DiagnosticLogLevel.error,
          component: 'home',
          operation: 'start_photo_import',
          result: 'failed',
          reason: DiagnosticLogEvent.reasonFor(error),
          durationMs: timer.elapsedMilliseconds,
        ),
      );
      if (mounted) {
        if (!_cancelPreparingRequested) {
          setState(() {
            _failedTask = task;
            _importError = context.l10n.photoImportFailed;
          });
        }
      }
    } finally {
      if (catalogTransactionStarted &&
          !importedProjectKept &&
          store is PhotoProjectCatalogStore) {
        try {
          await store.cancelNewProject();
        } on Object catch (error) {
          diagnosticLog.record(
            DiagnosticLogEvent(
              level: DiagnosticLogLevel.error,
              component: 'project_catalog',
              operation: 'cancel_new_project',
              result: 'failed',
              reason: DiagnosticLogEvent.reasonFor(error),
            ),
          );
          if (mounted && !_cancelPreparingRequested) {
            setState(
              () => _projectActionError = context.l10n.projectRestoreFailed,
            );
          }
        }
      }
      session?.dispose();
      if (mounted) {
        setState(() {
          _preparingTask = null;
          _cancelPreparingRequested = false;
        });
      }
    }
  }

  void _cancelPreparing() {
    if (_preparingTask == null) return;
    setState(() => _cancelPreparingRequested = true);
    final importer = _importer;
    if (importer is CancelablePhotoImporter) {
      unawaited(_cancelImport(importer));
    }
  }

  Future<void> _cancelImport(CancelablePhotoImporter importer) async {
    try {
      await importer.cancelImport();
    } on Object {
      // The import result remains authoritative and its timeout still bounds
      // a native cancellation failure.
    }
  }

  String _taskTitle(BuildContext context, CreationTask task) => switch (task) {
    CreationTask.optimize => context.l10n.optimizePhoto,
    CreationTask.style => context.l10n.homeChangeStyle,
    CreationTask.cleanup => context.l10n.removeBackgroundOrObjects,
    CreationTask.motion => context.l10n.createMotionEffect,
  };

  String _taskSubtitle(BuildContext context, CreationTask task) =>
      switch (task) {
        CreationTask.optimize => context.l10n.optimizePhotoSubtitle,
        CreationTask.style => context.l10n.changeStyleSubtitle,
        CreationTask.cleanup => context.l10n.removeBackgroundOrObjectsSubtitle,
        CreationTask.motion => context.l10n.createMotionEffectSubtitle,
      };

  Future<void> _deleteDraft(PhotoProject project) async {
    if (_preparingTask != null || _openingProjectId != null) return;
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
      setState(() => _projectActionError = context.l10n.projectDeleteFailed);
      return;
    }
    if (_preparingTask != null || _openingProjectId != null) return;
    setState(() => _openingProjectId = project.id);
    try {
      final generationCoordinator = _generationCoordinator;
      if (generationCoordinator != null) {
        await generationCoordinator.prepareProjectDeletion(project.id);
        // Persist the user's explicit deletion authorization before removing
        // the project. Recovery still checks the live project catalog, so a
        // failed project deletion can never trigger generation cleanup.
        await generationCoordinator.stageProjectDeletionCleanup(project.id);
      }
      await store.deleteProject(project);
      Object? generationCleanupError;
      try {
        await generationCoordinator?.deleteProjectState(project.id);
      } on Object catch (error) {
        generationCleanupError = error;
      }
      if (!mounted) return;
      if (generationCleanupError == null) {
        setState(() => _projectActionError = null);
      } else {
        setState(
          () => _projectActionError =
              context.l10n.projectDeletedGenerationCleanupPending,
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _projectActionError = error is GenerationProjectDeletionBlocked
              ? context.l10n.projectDeleteCloudTaskActive
              : context.l10n.projectDeleteFailed,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingProjectId = null);
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('home-page'),
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        key: const ValueKey('home-full-screen-background'),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.black,
            gradient: RadialGradient(
              center: Alignment(0.9, -1.05),
              radius: 0.8,
              colors: [Color(0x1AFFD66B), Colors.black],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: FutureBuilder<List<PhotoProject>>(
              future: _projects,
              builder: (context, snapshot) {
                final projects = snapshot.data ?? const <PhotoProject>[];
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(
                    key: const ValueKey('home-scroll'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      _HomeHeader(
                        onSettings:
                            _preparingTask == null && _openingProjectId == null
                            ? () => Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.settings)
                            : null,
                      ),
                      const SizedBox(height: 22),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (index, task)
                              in CreationTask.values.indexed)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: index == CreationTask.values.length - 1
                                    ? 0
                                    : 12,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _TaskTile(
                                    key: ValueKey('home-${task.name}'),
                                    task: task,
                                    title: _taskTitle(context, task),
                                    subtitle: _taskSubtitle(context, task),
                                    enabled:
                                        _preparingTask == null &&
                                        _openingProjectId == null,
                                    preparing: _preparingTask == task,
                                    onTap: () => _startNew(task),
                                  ),
                                  if (_preparingTask == task)
                                    _PreparingControl(
                                      cancelRequested:
                                          _cancelPreparingRequested,
                                      onCancel: _cancelPreparing,
                                    ),
                                  if (_failedTask == task)
                                    _ImportRecovery(
                                      message: _importError,
                                      failures: _importFailures,
                                      onRetry: () => _startNew(task),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) ...[
                        const SizedBox(height: 18),
                        const LinearProgressIndicator(minHeight: 2),
                      ] else if (snapshot.hasError) ...[
                        const SizedBox(height: 18),
                        _RestoreFailure(onRetry: _reload),
                      ] else if (projects.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        Text(
                          context.l10n.recentCreations,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        for (var index = 0; index < projects.length; index++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: index == projects.length - 1 ? 0 : 10,
                            ),
                            child: _RecentCreationCard(
                              key: index == 0
                                  ? ValueKey(
                                      'home-featured-draft-${projects[index].id}',
                                    )
                                  : ValueKey(
                                      'home-draft-${projects[index].id}',
                                    ),
                              project: projects[index],
                              latest: index == 0,
                              onTap:
                                  _preparingTask == null &&
                                      _openingProjectId == null
                                  ? () => _openCreation(projects[index])
                                  : null,
                              onDelete:
                                  _preparingTask == null &&
                                      _openingProjectId == null
                                  ? () => _deleteDraft(projects[index])
                                  : null,
                            ),
                          ),
                      ],
                      if (_projectActionError != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _projectActionError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onSettings});

  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 9,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _BrandMark(),
                Text(
                  context.l10n.appTitle,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.homeChooseResult,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
            ),
          ],
        ),
      ),
      IconButton(
        key: const ValueKey('home-settings'),
        tooltip: context.l10n.settings,
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: AppTheme.gold, width: 1.5),
    ),
    child: const Icon(
      Icons.auto_awesome_rounded,
      size: 16,
      color: AppTheme.gold,
    ),
  );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.preparing,
    required this.onTap,
    super.key,
  });

  final CreationTask task;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool preparing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 350 || textScale > 1.35;
        return Semantics(
          button: true,
          enabled: enabled,
          liveRegion: preparing,
          label: preparing
              ? '$title，${context.l10n.preparingImage}'
              : '$title，$subtitle',
          child: Material(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: AnimatedSize(
                duration: MediaQuery.of(context).disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 124),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    preparing
                                        ? context.l10n.preparingImage
                                        : subtitle,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppTheme.muted),
                                  ),
                                ],
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 112,
                                height: 104,
                                child: switch (task) {
                                  CreationTask.optimize =>
                                    const _OptimizeTaskPreview(),
                                  CreationTask.style =>
                                    const _ApplyTaskPreview(),
                                  CreationTask.cleanup =>
                                    const _CleanupTaskPreview(),
                                  CreationTask.motion =>
                                    const _MotionTaskPreview(),
                                },
                              ),
                            ],
                            const SizedBox(width: 8),
                            if (preparing)
                              const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.muted,
                              ),
                          ],
                        ),
                      ),
                      if (preparing) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          key: ValueKey('home-${task.name}-preparing'),
                          minHeight: 2,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreparingControl extends StatelessWidget {
  const _PreparingControl({
    required this.cancelRequested,
    required this.onCancel,
  });

  final bool cancelRequested;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: const ValueKey('home-cancel-import'),
      onPressed: cancelRequested ? null : onCancel,
      child: Text(context.l10n.cancel),
    ),
  );
}

class _OptimizeTaskPreview extends StatelessWidget {
  const _OptimizeTaskPreview();

  @override
  Widget build(BuildContext context) => const _TaskGlyphPreview(
    icon: Icons.auto_fix_high_rounded,
    colors: [Color(0xFF725D2A), Color(0xFF302D23)],
    accent: Color(0xFFFFD66B),
  );
}

class _CleanupTaskPreview extends StatelessWidget {
  const _CleanupTaskPreview();

  @override
  Widget build(BuildContext context) => const _TaskGlyphPreview(
    icon: Icons.content_cut_rounded,
    colors: [Color(0xFF49606A), Color(0xFF232A2F)],
    accent: Color(0xFFE0F1F8),
  );
}

class _TaskGlyphPreview extends StatelessWidget {
  const _TaskGlyphPreview({
    required this.icon,
    required this.colors,
    required this.accent,
  });

  final IconData icon;
  final List<Color> colors;
  final Color accent;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ),
    ),
    child: Center(child: Icon(icon, size: 46, color: accent)),
  );
}

class _ApplyTaskPreview extends StatelessWidget {
  const _ApplyTaskPreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF66717A), Color(0xFF252A2E)],
            ),
          ),
        ),
        const Align(
          alignment: Alignment(0, 0.35),
          child: Icon(Icons.person_rounded, size: 74, color: Color(0xFFD3D6D8)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: 0.5,
            child: ColoredBox(
              color: const Color(0x30FFD66B),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.center,
          child: VerticalDivider(width: 1, thickness: 1, color: Colors.white54),
        ),
      ],
    ),
  );
}

class _MotionTaskPreview extends StatelessWidget {
  const _MotionTaskPreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF525E58), Color(0xFF18201D)],
            ),
          ),
        ),
        const Align(
          alignment: Alignment(0, 0.45),
          child: Icon(
            Icons.landscape_rounded,
            size: 78,
            color: Color(0xFF9DB5A8),
          ),
        ),
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xCCF2F2F7),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.black,
              size: 28,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ImportRecovery extends StatelessWidget {
  const _ImportRecovery({
    required this.message,
    required this.failures,
    required this.onRetry,
  });

  final String? message;
  final List<PhotoImportFailure> failures;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message != null)
            Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final failure in failures)
            Text(
              _photoImportFailureMessage(context, failure),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          TextButton.icon(
            key: const ValueKey('home-import-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.retry),
          ),
        ],
      ),
    ),
  );
}

class _RecentCreationCard extends StatelessWidget {
  const _RecentCreationCard({
    required this.project,
    required this.latest,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final PhotoProject project;
  final bool latest;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final photo = project.photos.first;
    final local = project.updatedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final taskName = switch (project.creationTask) {
      CreationTask.optimize => context.l10n.optimizePhoto,
      CreationTask.style => context.l10n.homeChangeStyle,
      CreationTask.cleanup => context.l10n.removeBackgroundOrObjects,
      CreationTask.motion => context.l10n.createMotionEffect,
    };
    return Material(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Image.file(
                    File(photo.localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Color(0xFF2C2C2E),
                      child: Icon(Icons.photo_outlined),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taskName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 4),
                    Text(
                      _draftStatusLabel(context, project),
                      key: ValueKey('home-draft-status-${project.id}'),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: AppTheme.gold),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton(
                    key: latest
                        ? const ValueKey('home-resume-project')
                        : ValueKey('home-continue-draft-${project.id}'),
                    tooltip: context.l10n.continueCreation,
                    onPressed: onTap,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  IconButton(
                    key: ValueKey('home-delete-draft-${project.id}'),
                    tooltip: context.l10n.deleteDraft,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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

String _draftStatusLabel(BuildContext context, PhotoProject project) {
  if (project.requiresUpdate) return context.l10n.draftStatusNeedsUpdate;
  final exportedVersion = project.lastSuccessfulExportEditStateVersion;
  if (exportedVersion == null) return context.l10n.draftStatusEditing;
  return exportedVersion == project.editStateVersion
      ? context.l10n.draftStatusExported
      : context.l10n.draftStatusModified;
}

String _photoImportFailureMessage(
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
