import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/l10n/l10n.dart';
import 'package:yingjian/observability/analytics_event.dart';
import 'package:yingjian/observability/app_observability.dart';
import 'package:yingjian/review/review_manager.dart';

final class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final observability = context.watch<AppObservability>();
    final diagnosticsBusy =
        observability.status == ObservabilityStatus.initializing;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              context.l10n.privacyAndDiagnostics,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SwitchListTile.adaptive(
            value: settings.diagnosticsEnabled,
            onChanged: diagnosticsBusy
                ? null
                : (value) => _setDiagnostics(context, value),
            title: Text(context.l10n.anonymousDiagnostics),
            subtitle: Text(_diagnosticsDescription(context, observability)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(context.l10n.privacyPolicy),
            subtitle: Text(context.l10n.privacyPolicyDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.privacy),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.termsOfUse),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.terms),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.star_outline),
            title: Text(context.l10n.rateApp),
            subtitle: Text(context.l10n.rateAppDescription),
            onTap: () => _openStoreListing(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(context.l10n.openSourceLicenses),
            onTap: () => showLicensePage(
              context: context,
              applicationName: context.l10n.appTitle,
            ),
          ),
        ],
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
      if (!context.mounted) {
        return;
      }
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
}
