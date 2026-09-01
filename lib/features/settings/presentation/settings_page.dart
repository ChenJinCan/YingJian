import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/app/theme/app_theme.dart';
import 'package:yingjian/features/project/application/photo_project_session.dart';
import 'package:yingjian/features/photo_analysis/application/photo_analysis_cache.dart';
import 'package:yingjian/l10n/l10n.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/review/review_manager.dart';

final class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

final class _SettingsPageState extends State<SettingsPage> {
  int _versionTapCount = 0;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final observability = context.watch<AppObservability>();
    final diagnosticsBusy =
        observability.status == ObservabilityStatus.initializing;

    return Scaffold(
      key: const ValueKey('settings-page'),
      backgroundColor: AppTheme.canvas,
      appBar: AppBar(
        title: Text(
          context.l10n.settings,
          style: const TextStyle(
            color: AppTheme.gold,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
        children: [
          _SectionLabel(text: _zh(context) ? '外观与语言' : 'Appearance & language'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                key: const ValueKey('settings-appearance'),
                title: _zh(context) ? '外观' : 'Appearance',
                value: _themeLabel(context, settings.themeMode),
                onTap: () => _chooseTheme(context, settings),
              ),
              _SettingsRow(
                key: const ValueKey('settings-language'),
                title: _zh(context) ? '语言' : 'Language',
                value: _localeLabel(context, settings.locale),
                onTap: () => _chooseLocale(context, settings),
              ),
            ],
          ),
          _SectionLabel(text: _zh(context) ? '导出画质与存储' : 'Export & storage'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                key: const ValueKey('settings-export-quality'),
                title: _zh(context) ? '导出画质' : 'Export quality',
                value: _qualityLabel(context, settings.exportQuality),
                onTap: () => _chooseQuality(context, settings),
              ),
              _SettingsRow(
                key: const ValueKey('settings-manage-cache'),
                title: _zh(context) ? '管理缓存' : 'Manage cache',
                onTap: () => _clearCache(context),
              ),
            ],
          ),
          _SectionLabel(text: _zh(context) ? '隐私与权限' : 'Privacy & permissions'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                key: const ValueKey('settings-local-processing'),
                title: _zh(context) ? '照片本机处理说明' : 'On-device processing',
                onTap: () => _showLocalProcessing(context),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('settings-anonymous-diagnostics'),
                value: settings.diagnosticsEnabled,
                onChanged: diagnosticsBusy
                    ? null
                    : (value) => _setDiagnostics(context, value),
                activeThumbColor: AppTheme.gold,
                title: Text(context.l10n.anonymousDiagnostics),
                subtitle: Text(
                  _diagnosticsDescription(context, observability),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          _SectionLabel(text: _zh(context) ? '帮助与关于' : 'Help & about'),
          _SettingsGroup(
            children: [
              _SettingsRow(
                key: const ValueKey('settings-legal'),
                title: _zh(context) ? '用户协议与隐私政策' : 'Terms & privacy',
                onTap: () => _showLegalChoices(context),
              ),
              _SettingsRow(
                key: const ValueKey('settings-rate'),
                title: context.l10n.rateApp,
                onTap: () => _openStoreListing(context),
              ),
              _SettingsRow(
                key: const ValueKey('settings-licenses'),
                title: context.l10n.openSourceLicenses,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: context.l10n.appTitle,
                ),
              ),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) => _SettingsRow(
                  key: const ValueKey('settings-version'),
                  title: _zh(context) ? '版本' : 'Version',
                  value: snapshot.data?.version ?? '—',
                  showChevron: false,
                  onTap: () => _onVersionTap(context, settings),
                ),
              ),
              if (settings.developerLogsUnlocked)
                _SettingsRow(
                  key: const ValueKey('settings-developer-logs'),
                  title: _zh(context) ? '诊断日志' : 'Diagnostic logs',
                  onTap: () =>
                      Navigator.of(context).pushNamed(AppRoutes.developerLogs),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _zh(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh';

  static String _themeLabel(BuildContext context, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => _zh(context) ? '跟随系统' : 'System',
        ThemeMode.light => _zh(context) ? '浅色' : 'Light',
        ThemeMode.dark => _zh(context) ? '深色' : 'Dark',
      };

  static String _localeLabel(BuildContext context, Locale? locale) {
    if (locale == null) return _zh(context) ? '跟随系统' : 'System';
    return locale.languageCode == 'zh' ? '简体中文' : 'English';
  }

  static String _qualityLabel(BuildContext context, AppExportQuality quality) =>
      switch (quality) {
        AppExportQuality.high => context.l10n.exportQualityHigh,
        AppExportQuality.standard => context.l10n.exportQualityStandard,
        AppExportQuality.compact => context.l10n.exportQualityCompact,
      };

  Future<void> _chooseTheme(BuildContext context, AppSettings settings) async {
    final result = await _radioSheet<ThemeMode>(
      context,
      title: _zh(context) ? '外观' : 'Appearance',
      current: settings.themeMode,
      values: ThemeMode.values,
      label: (value) => _themeLabel(context, value),
    );
    if (result != null) await settings.setThemeMode(result);
  }

  Future<void> _chooseLocale(BuildContext context, AppSettings settings) async {
    const system = 'system';
    final current = settings.locale?.languageCode ?? system;
    final result = await _radioSheet<String>(
      context,
      title: _zh(context) ? '语言' : 'Language',
      current: current,
      values: const [system, 'zh', 'en'],
      label: (value) => switch (value) {
        system => _zh(context) ? '跟随系统' : 'System',
        'zh' => '简体中文',
        _ => 'English',
      },
    );
    if (result == null) return;
    await settings.setLocale(result == system ? null : Locale(result));
  }

  Future<void> _chooseQuality(
    BuildContext context,
    AppSettings settings,
  ) async {
    final result = await _radioSheet<AppExportQuality>(
      context,
      title: _zh(context) ? '导出画质' : 'Export quality',
      current: settings.exportQuality,
      values: AppExportQuality.values,
      label: (value) => _qualityLabel(context, value),
    );
    if (result != null) await settings.setExportQuality(result);
  }

  Future<T?> _radioSheet<T>(
    BuildContext context, {
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) label,
  }) => showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
        child: RadioGroup<T>(
          groupValue: current,
          onChanged: (selected) => Navigator.of(sheetContext).pop(selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final value in values)
                RadioListTile<T>(
                  value: value,
                  activeColor: AppTheme.gold,
                  title: Text(label(value)),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _clearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_zh(context) ? '清理缓存？' : 'Clear cache?'),
        content: Text(
          _zh(context)
              ? '只清理可重新生成的预览与分析缓存，不删除原图、项目或编辑记录。'
              : 'Only regenerable previews and analysis data are cleared. Photos and edits stay intact.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_zh(context) ? '清理' : 'Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    final cache = context.read<PhotoAnalysisCache>();
    final project = await context.read<PhotoProjectStore>().loadLatest();
    if (project != null) {
      await cache.clearProject(project.id);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_zh(context) ? '缓存已清理' : 'Cache cleared')),
    );
  }

  void _showLocalProcessing(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _zh(context) ? '照片默认在本机处理' : 'Photos stay on device by default',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                _zh(context)
                    ? '导入、分析、参数预览和导出默认都在本机完成。映见不会因为浏览推荐或手动调整而上传原图。'
                    : 'Import, analysis, parameter previews, and export run locally. Browsing looks or adjusting tools does not upload originals.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: Text(_zh(context) ? '知道了' : 'Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLegalChoices(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('settings-privacy-policy'),
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(context.l10n.privacyPolicy),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.privacy);
              },
            ),
            ListTile(
              key: const ValueKey('settings-terms-of-use'),
              leading: const Icon(Icons.description_outlined),
              title: Text(context.l10n.termsOfUse),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed(AppRoutes.terms);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _diagnosticsDescription(
    BuildContext context,
    AppObservability observability,
  ) {
    if (observability.status == ObservabilityStatus.unavailable) {
      return context.l10n.diagnosticsUnavailableDescription;
    }
    return context.read<AppSettings>().diagnosticsEnabled
        ? context.l10n.diagnosticsOnDescription
        : context.l10n.diagnosticsOffDescription;
  }

  Future<void> _setDiagnostics(BuildContext context, bool enabled) async {
    final settings = context.read<AppSettings>();
    final observability = context.read<AppObservability>();
    if (enabled) {
      final available = await observability.setCollectionEnabled(true);
      if (!context.mounted) return;
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.diagnosticsEnableFailed)),
        );
        return;
      }
      await observability.track(
        AnalyticsEvent(
          AnalyticsEventName.diagnosticsPreferenceChanged,
          parameters: const {
            AnalyticsParameter.action: 'enable',
            AnalyticsParameter.result: 'success',
          },
        ),
      );
      await settings.setDiagnosticsEnabled(true);
      return;
    }
    await observability.track(
      AnalyticsEvent(
        AnalyticsEventName.diagnosticsPreferenceChanged,
        parameters: const {
          AnalyticsParameter.action: 'disable',
          AnalyticsParameter.result: 'success',
        },
      ),
    );
    await observability.setCollectionEnabled(false);
    await settings.setDiagnosticsEnabled(false);
  }

  Future<void> _openStoreListing(BuildContext context) async {
    final opened = await context.read<ReviewManager>().openStoreListing();
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.storeListingUnavailable)),
      );
    }
  }

  Future<void> _onVersionTap(BuildContext context, AppSettings settings) async {
    if (settings.developerLogsUnlocked) {
      await Navigator.of(context).pushNamed(AppRoutes.developerLogs);
      return;
    }
    _versionTapCount += 1;
    if (_versionTapCount < 5) return;
    _versionTapCount = 0;
    await settings.unlockDeveloperLogs();
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(AppRoutes.developerLogs);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 20, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: const Color(0xFFD1C5AF),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1E2021),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 18, endIndent: 18),
          children[index],
        ],
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    this.value,
    this.onTap,
    this.showChevron = true,
    super.key,
  });

  final String title;
  final String? value;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 54,
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value != null)
          Text(
            value!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD1C5AF),
              fontWeight: FontWeight.w600,
            ),
          ),
        if (showChevron) ...[
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, size: 22),
        ],
      ],
    ),
    onTap: onTap,
  );
}
