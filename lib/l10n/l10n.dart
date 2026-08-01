import 'package:flutter/widgets.dart';
import 'package:yingjian/l10n/app_localizations.dart';

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
