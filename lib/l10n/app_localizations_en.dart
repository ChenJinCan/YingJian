// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Yingjian';

  @override
  String get homeTagline => 'Refine one. Unify the whole set.';

  @override
  String get startEditing => 'Start editing';

  @override
  String get editorTitle => 'Fine-tuning workspace';

  @override
  String get undo => 'Undo';

  @override
  String get reset => 'Reset';

  @override
  String get photoPreviewArea => 'Photo preview';

  @override
  String get exposure => 'Exposure';

  @override
  String get contrast => 'Contrast';

  @override
  String get warmth => 'Warmth';

  @override
  String get unknownPageTitle => 'Page not found';

  @override
  String get unknownPageMessage => 'This page cannot be opened right now';
}
