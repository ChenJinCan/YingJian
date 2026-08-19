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
      await Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            key: const ValueKey('onboarding-full-screen-background'),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 16),
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
                  const Spacer(flex: 2),
                  Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.primary.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 24,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    context.l10n.homeHeroTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.homeTagline,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const Spacer(flex: 2),
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
          ),
        ],
      ),
    );
  }
}
