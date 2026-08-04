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
  String get selectPhotosTitle => 'Choose 1–9 photos';

  @override
  String get selectPhotos => 'Choose photos';

  @override
  String get addPhotos => 'Add more photos';

  @override
  String get photoImportPrivacy =>
      'Photos are copied only into your local Yingjian project and are not uploaded just because you selected them.';

  @override
  String photoCount(int count) {
    return '$count/9';
  }

  @override
  String get photoLoadFailed => 'This photo cannot be opened';

  @override
  String get photoImportFailed => 'Photo import failed. Try again.';

  @override
  String get photoLimitReached => 'A project can contain up to 9 photos';

  @override
  String get projectRestoreFailed =>
      'Your previous project could not be restored';

  @override
  String get projectSaveFailed =>
      'This adjustment could not be saved. Try again.';

  @override
  String get retry => 'Try again';

  @override
  String get exposure => 'Exposure';

  @override
  String get contrast => 'Contrast';

  @override
  String get warmth => 'Warmth';

  @override
  String get exportOriginalQuality => 'Export at original quality';

  @override
  String photoExported(int width, int height) {
    return 'Saved to Photos ($width × $height)';
  }

  @override
  String get photoExportFailed =>
      'Export failed. Check photo access and try again.';

  @override
  String get unknownPageTitle => 'Page not found';

  @override
  String get unknownPageMessage => 'This page cannot be opened right now';

  @override
  String get settings => 'Settings';

  @override
  String get privacyAndDiagnostics => 'Privacy and diagnostics';

  @override
  String get anonymousDiagnostics => 'Anonymous diagnostics';

  @override
  String get diagnosticsOffDescription =>
      'Off by default; no analytics, crash, or performance data is sent';

  @override
  String get diagnosticsOnDescription =>
      'Sends minimized anonymous diagnostics';

  @override
  String get diagnosticsUnavailableDescription =>
      'The independent Yingjian Firebase project is not configured';

  @override
  String get diagnosticsEnableFailed =>
      'Diagnostics are unavailable and remain disabled';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicyDescription =>
      'How photos, diagnostics, and third parties handle data';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get rateApp => 'Rate this app';

  @override
  String get rateAppDescription => 'Open the app store review page';

  @override
  String get storeListingUnavailable =>
      'The app store listing is not configured';

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String get legalDocumentLoadFailed =>
      'This document cannot be loaded right now';
}
