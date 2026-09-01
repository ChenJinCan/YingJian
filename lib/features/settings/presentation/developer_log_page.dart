import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/observability/local_diagnostic_log.dart';

enum _LogFilter { all, errors, photoImport }

final class DeveloperLogPage extends StatefulWidget {
  const DeveloperLogPage({super.key});

  @override
  State<DeveloperLogPage> createState() => _DeveloperLogPageState();
}

final class _DeveloperLogPageState extends State<DeveloperLogPage> {
  List<DiagnosticLogEntry> _entries = const [];
  _LogFilter _filter = _LogFilter.all;
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final entries = await context.read<DiagnosticLog>().readEntries();
      if (!mounted) return;
      setState(() => _entries = entries);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DiagnosticLogEntry> get _visibleEntries => switch (_filter) {
    _LogFilter.all => _entries,
    _LogFilter.errors =>
      _entries
          .where((entry) => entry.level == DiagnosticLogLevel.error)
          .toList(growable: false),
    _LogFilter.photoImport =>
      _entries
          .where(
            (entry) =>
                entry.component == 'photo_import' ||
                entry.operation.contains('photo_import') ||
                entry.operation.contains('picker'),
          )
          .toList(growable: false),
  };

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      key: const ValueKey('developer-log-page'),
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        title: Text(zh ? '诊断日志' : 'Diagnostic logs'),
        actions: [
          IconButton(
            key: const ValueKey('developer-log-copy-all'),
            tooltip: zh ? '复制当前日志' : 'Copy visible logs',
            onPressed: _visibleEntries.isEmpty ? null : _copyVisible,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            key: const ValueKey('developer-log-clear'),
            tooltip: zh ? '清空日志' : 'Clear logs',
            onPressed: _entries.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                zh
                    ? '仅保存在本机；不记录照片内容、文件名或路径。'
                    : 'Stored only on this device. Photo content, names, and paths are never logged.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SegmentedButton<_LogFilter>(
                segments: [
                  ButtonSegment(
                    value: _LogFilter.all,
                    label: Text(zh ? '全部' : 'All'),
                  ),
                  ButtonSegment(
                    value: _LogFilter.errors,
                    label: Text(zh ? '错误' : 'Errors'),
                  ),
                  ButtonSegment(
                    value: _LogFilter.photoImport,
                    label: Text(zh ? '照片导入' : 'Photo import'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) {
                  setState(() => _filter = selection.single);
                },
              ),
            ),
            Expanded(child: _buildBody(zh)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool zh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: FilledButton.icon(
          key: const ValueKey('developer-log-retry'),
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(zh ? '读取失败，重试' : 'Could not load. Retry'),
        ),
      );
    }
    final entries = _visibleEntries;
    if (entries.isEmpty) {
      return Center(
        key: const ValueKey('developer-log-empty'),
        child: Text(zh ? '暂无符合条件的日志' : 'No matching logs'),
      );
    }
    return SelectionArea(
      child: ListView.separated(
        key: const ValueKey('developer-log-list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1E2021),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _levelColor(entry.level).withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                entry.displayText,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _levelColor(entry.level),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _copyVisible() async {
    final text = _visibleEntries.map((entry) => entry.displayText).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(zh ? '日志已复制' : 'Logs copied')));
  }

  Future<void> _confirmClear() async {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final diagnosticLog = context.read<DiagnosticLog>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zh ? '清空诊断日志？' : 'Clear diagnostic logs?'),
        content: Text(zh ? '此操作只删除本机日志。' : 'This only removes local logs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(zh ? '取消' : 'Cancel'),
          ),
          FilledButton(
            key: const ValueKey('developer-log-confirm-clear'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(zh ? '清空' : 'Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await diagnosticLog.clear();
    if (!mounted) return;
    setState(() => _entries = const []);
  }

  static Color _levelColor(DiagnosticLogLevel level) => switch (level) {
    DiagnosticLogLevel.info => AppTheme.softWhite,
    DiagnosticLogLevel.warning => AppTheme.gold,
    DiagnosticLogLevel.error => const Color(0xFFFF8A80),
  };
}
