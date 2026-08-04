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
  String get redo => 'Redo';

  @override
  String get reset => 'Reset';

  @override
  String get photoPreviewArea => 'Photo preview';

  @override
  String get selectPhotosTitle => 'Choose 1–6 photos';

  @override
  String get selectPhotos => 'Choose photos';

  @override
  String get addPhotos => 'Add more photos';

  @override
  String get photoImportPrivacy =>
      'Photos are copied only into your local Yingjian project and are not uploaded just because you selected them.';

  @override
  String photoCount(int count) {
    return '$count/6';
  }

  @override
  String get photoLoadFailed => 'This photo cannot be opened';

  @override
  String get photoImportFailed => 'Photo import failed. Try again.';

  @override
  String get photoImportIssuesTitle => 'Some photos were not imported';

  @override
  String photoUnsupportedFormat(String name) {
    return '$name: this format is not supported';
  }

  @override
  String photoAnimatedUnsupported(String name) {
    return '$name: animated images are not supported';
  }

  @override
  String photoFileTooLarge(String name) {
    return '$name: the file is larger than 100 MB';
  }

  @override
  String photoDimensionsTooLarge(String name) {
    return '$name: exceeds 48 MP or a 12,000 px edge';
  }

  @override
  String photoUnreadable(String name) {
    return '$name: the image is damaged or unreadable';
  }

  @override
  String photoCopyFailed(String name) {
    return '$name: a local working copy could not be created';
  }

  @override
  String get photoLimitReached => 'A project can contain up to 6 photos';

  @override
  String get projectRestoreFailed =>
      'Your previous project could not be restored';

  @override
  String get projectSaveFailed =>
      'This adjustment could not be saved. Try again.';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String get removePhotoConfirmation =>
      'This removes only Yingjian\'s local project copy. The original in Photos is not changed.';

  @override
  String get deleteProject => 'Delete project';

  @override
  String get deleteProjectConfirmation =>
      'Delete this project and Yingjian\'s working copies? Originals in Photos will not be deleted.';

  @override
  String get movePhotoEarlier => 'Move earlier';

  @override
  String get movePhotoLater => 'Move later';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Try again';

  @override
  String get exposure => 'Exposure';

  @override
  String get highlights => 'Highlights';

  @override
  String get shadows => 'Shadows';

  @override
  String get contrast => 'Contrast';

  @override
  String get warmth => 'Warmth';

  @override
  String get tint => 'Tint';

  @override
  String get saturation => 'Saturation';

  @override
  String get clarity => 'Clarity';

  @override
  String get composition => 'Composition';

  @override
  String get straighten => 'Straighten';

  @override
  String get rotateLeft => 'Rotate left';

  @override
  String get rotateRight => 'Rotate right';

  @override
  String get originalCrop => 'Original';

  @override
  String get cropSquare => '1:1';

  @override
  String get cropFourThree => '4:3';

  @override
  String get cropSixteenNine => '16:9';

  @override
  String get resetComposition => 'Reset composition';

  @override
  String get compareOriginal => 'View original';

  @override
  String get compareEdited => 'Back to edit';

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
