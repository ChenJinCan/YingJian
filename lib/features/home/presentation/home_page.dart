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
    return Scaffold(
      appBar: AppBar(
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
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.appTitle,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.homeTagline,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 32),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      Column(
                        children: [
                          const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            key: const ValueKey('home-start-editing'),
                            onPressed: _openEditor,
                            child: Text(context.l10n.startEditing),
                          ),
                        ],
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
                      FilledButton(
                        key: const ValueKey('home-start-editing'),
                        onPressed: _openEditor,
                        child: Text(context.l10n.startEditing),
                      ),
                  ],
                ),
              ),
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
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.unfinishedProject,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(summary),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('home-resume-project'),
              onPressed: onContinue,
              child: Text(context.l10n.continueLastEditing),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onStartNew,
              child: Text(context.l10n.startNewProject),
            ),
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
