import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yingjian/app/navigation/app_router.dart';
import 'package:yingjian/app/settings/app_settings.dart';
import 'package:yingjian/l10n/l10n.dart';

final class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

final class _OnboardingPageState extends State<OnboardingPage> {
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<AppSettings>().completeOnboarding();
      if (!mounted) return;
      await Navigator.of(context).pushReplacementNamed(AppRoutes.home);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.onboardingSaveFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('onboarding-page'),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.primary.withValues(alpha: 0.18),
                      colors.surface.withValues(alpha: 0),
                      colors.surface,
                    ],
                    stops: const [0, 0.46, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 54,
                    color: colors.primary,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    context.l10n.homeHeroTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.onboardingPromise,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    container: true,
                    label: context.l10n.onboardingPrivacy,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.7,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: colors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(context.l10n.onboardingPrivacy),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('onboarding-continue'),
                    onPressed: _saving ? null : _continue,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(58),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.l10n.onboardingContinue),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        key: const ValueKey('onboarding-privacy'),
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.privacy),
                        child: Text(context.l10n.privacyPolicy),
                      ),
                      Text('·', style: TextStyle(color: colors.outline)),
                      TextButton(
                        key: const ValueKey('onboarding-terms'),
                        onPressed: () =>
                            Navigator.of(context).pushNamed(AppRoutes.terms),
                        child: Text(context.l10n.termsOfUse),
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
