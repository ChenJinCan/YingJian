import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
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
    final latestProject = _store!.loadLatest();
    setState(() {
      _latestProject = latestProject;
    });
  }

  Future<void> _openEditor() async {
    await Navigator.of(context).pushNamed(AppRoutes.editor);
    if (mounted) _reload();
  }

  Future<void> _startNew(PhotoProject project) async {
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
    await _openEditor();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n.appTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        actions: [
          IconButton(
            key: const ValueKey('home-settings'),
            tooltip: context.l10n.settings,
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<PhotoProject?>(
          future: _latestProject,
          builder: (context, snapshot) {
            final project = snapshot.data;
            return Stack(
              children: [
                Positioned(
                  top: -130,
                  left: -90,
                  right: -90,
                  child: IgnorePointer(
                    child: Container(
                      height: 310,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            colors.primary.withValues(alpha: 0.12),
                            colors.surface.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 30, 22, 22),
                          child: Column(
                            children: [
                              const _YingjianMark(),
                              const SizedBox(height: 20),
                              Text(
                                context.l10n.homeHeroTitle,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.l10n.homeTagline,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                              const SizedBox(height: 26),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  key: const ValueKey('home-start-editing'),
                                  onPressed: _openEditor,
                                  icon: const Icon(Icons.add_photo_alternate),
                                  label: Text(context.l10n.startEditing),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        context.l10n.recentProjects,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const SizedBox(
                          height: 96,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (snapshot.hasError)
                        _RestoreFailure(onRetry: _reload)
                      else if (project != null)
                        _ProjectResumeCard(
                          project: project,
                          onContinue: _openEditor,
                          onStartNew: () => _startNew(project),
                        )
                      else
                        _EmptyRecentProject(onStart: _openEditor),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProjectResumeCard extends StatelessWidget {
  const _ProjectResumeCard({
    required this.project,
    required this.onContinue,
    required this.onStartNew,
  });

  final PhotoProject project;
  final VoidCallback onContinue;
  final VoidCallback onStartNew;

  @override
  Widget build(BuildContext context) {
    final localUpdatedAt = project.updatedAt.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final summary = context.l10n.lastProjectSummary(
      project.photos.length,
      localizations.formatCompactDate(localUpdatedAt),
      localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(localUpdatedAt),
        alwaysUse24HourFormat: true,
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.photo_library_outlined, size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
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
                    summary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: onStartNew,
                        child: Text(context.l10n.startNewProject),
                      ),
                      FilledButton(
                        key: const ValueKey('home-resume-project'),
                        onPressed: onContinue,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 44),
                        ),
                        child: Text(context.l10n.continueLastEditing),
                      ),
                    ],
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

class _YingjianMark extends StatelessWidget {
  const _YingjianMark();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors.primary.withValues(alpha: 0.1),
        border: Border.all(color: colors.primary.withValues(alpha: 0.28)),
      ),
      child: Icon(Icons.auto_awesome, color: colors.primary, size: 32),
    );
  }
}

class _EmptyRecentProject extends StatelessWidget {
  const _EmptyRecentProject({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.history, size: 28),
              const SizedBox(width: 14),
              Expanded(child: Text(context.l10n.noRecentProjects)),
              const Icon(Icons.chevron_right),
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
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          const Icon(Icons.error_outline),
          const SizedBox(height: 8),
          Text(context.l10n.projectRestoreFailed),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: Text(context.l10n.retry)),
        ],
      ),
    );
  }
}
