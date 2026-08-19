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

  Future<void> _openEditor({bool startWithImport = false}) async {
    await Navigator.of(
      context,
    ).pushNamed(AppRoutes.editor, arguments: startWithImport);
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
    await _openEditor(startWithImport: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: FutureBuilder<PhotoProject?>(
        future: _latestProject,
        builder: (context, snapshot) {
          final project = snapshot.data;
          return Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('home-full-screen-background'),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-0.72, -1.02),
                      radius: 1.12,
                      colors: [
                        colors.primary.withValues(alpha: 0.16),
                        colors.surface,
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        24,
                        kToolbarHeight + 28,
                        24,
                        36,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 64),
                          const Center(child: _YingjianMark()),
                          const SizedBox(height: 18),
                          Text(
                            context.l10n.homeSupporting,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 26),
                          FilledButton.icon(
                            key: const ValueKey('home-start-editing'),
                            onPressed: project == null
                                ? () => _openEditor(startWithImport: true)
                                : () => _startNew(project),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                            ),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(context.l10n.homePrimaryAction),
                          ),
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) ...[
                            const SizedBox(height: 32),
                            const LinearProgressIndicator(minHeight: 2),
                          ] else if (snapshot.hasError) ...[
                            const SizedBox(height: 32),
                            _RestoreFailure(onRetry: _reload),
                          ] else if (project != null) ...[
                            const SizedBox(height: 72),
                            Text(
                              context.l10n.recentProjects,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            _ProjectResumeCard(
                              project: project,
                              onContinue: _openEditor,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 8,
                      child: IconButton(
                        key: const ValueKey('home-settings'),
                        tooltip: context.l10n.settings,
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.settings),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectResumeCard extends StatelessWidget {
  const _ProjectResumeCard({required this.project, required this.onContinue});

  final PhotoProject project;
  final VoidCallback onContinue;

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
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('home-resume-project'),
        onTap: onContinue,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.photo_library_outlined, size: 28),
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.34)),
          ),
          child: Icon(Icons.auto_awesome, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 14),
        Text(
          context.l10n.appTitle,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
      ],
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
