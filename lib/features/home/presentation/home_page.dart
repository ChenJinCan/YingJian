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
      appBar: AppBar(
        title: null,
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
                  top: -180,
                  left: -160,
                  right: -40,
                  child: IgnorePointer(
                    child: Container(
                      height: 420,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            colors.primary.withValues(alpha: 0.15),
                            colors.surface.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _YingjianMark(),
                      ),
                      const SizedBox(height: 34),
                      Text(
                        context.l10n.homeHeroTitle,
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.08,
                              letterSpacing: -1.1,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.homeTagline,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.homeSupporting,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 34),
                      FilledButton.icon(
                        key: const ValueKey('home-start-editing'),
                        onPressed: project == null
                            ? () => _openEditor(startWithImport: true)
                            : _openEditor,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(60),
                        ),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          project == null
                              ? context.l10n.homePrimaryAction
                              : context.l10n.continueLastEditing,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const _HomeJourneyGuide(),
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) ...[
                        const SizedBox(height: 32),
                        const LinearProgressIndicator(minHeight: 2),
                      ] else if (snapshot.hasError) ...[
                        const SizedBox(height: 32),
                        _RestoreFailure(onRetry: _reload),
                      ] else if (project != null) ...[
                        const SizedBox(height: 42),
                        Text(
                          context.l10n.recentProjects,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        _ProjectResumeCard(
                          project: project,
                          onContinue: _openEditor,
                          onStartNew: () => _startNew(project),
                        ),
                      ],
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
                        child: Text(context.l10n.openProject),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primary.withValues(alpha: 0.12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.34)),
          ),
          child: Icon(Icons.auto_awesome, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          context.l10n.appTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }
}

class _HomeJourneyGuide extends StatelessWidget {
  const _HomeJourneyGuide();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final steps = [
      (Icons.photo_library_outlined, context.l10n.homeStepChoose),
      (Icons.mic_none_outlined, context.l10n.homeStepDescribe),
      (Icons.done_all, context.l10n.homeStepSave),
    ];
    return Semantics(
      key: const ValueKey('home-journey-guide'),
      container: true,
      label: context.l10n.homeGuideSemantics,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(steps[index].$1, size: 20, color: colors.primary),
                    const SizedBox(height: 6),
                    Text(
                      steps[index].$2,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              if (index < steps.length - 1)
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ],
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
