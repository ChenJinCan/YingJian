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
  String get homeTagline => 'One photo. Refined with focus.';

  @override
  String get startEditing => 'Start editing';

  @override
  String get homeHeroTitle => 'Make beauty easier';

  @override
  String get homeSupporting =>
      'Choose a photo and tell us how you want it changed';

  @override
  String get homePrimaryAction => 'Choose a photo to start';

  @override
  String get onboardingPromise =>
      'Choose one photo, then describe the feeling you want. Yingjian focuses on refining that photo.';

  @override
  String get onboardingContinue => 'Get started';

  @override
  String get onboardingSaveFailed =>
      'We could not save your first-use choice. Please try again.';

  @override
  String get recentProjects => 'Recent projects';

  @override
  String get otherDrafts => 'Other drafts';

  @override
  String get selectNewPhoto => 'Choose a new photo';

  @override
  String get deleteDraft => 'Delete draft';

  @override
  String get draftDeleteConfirmation =>
      'This only deletes the draft in Yingjian. The original in Photos is not deleted.';

  @override
  String get draftStatusEditing => 'Editing';

  @override
  String get draftStatusExported => 'Exported';

  @override
  String get draftStatusModified => 'New changes';

  @override
  String get draftStatusNeedsUpdate => 'Update required';

  @override
  String get draftStatusNeedsRecovery => 'Recovery required';

  @override
  String lastEditedAt(String date, String time) {
    return 'Last edited $date $time';
  }

  @override
  String get noRecentProjects => 'No projects yet. Choose one photo to begin.';

  @override
  String get unfinishedProject => 'Unfinished project';

  @override
  String get continueLastEditing => 'Continue last editing';

  @override
  String get startNewProject => 'Start a new project';

  @override
  String get deleteAndStartNew => 'Delete and start new';

  @override
  String get projectDeleteFailed =>
      'The local project could not be deleted. Nothing was changed.';

  @override
  String lastProjectSummary(int count, String date, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count photos',
      one: '1 photo',
    );
    return '$_temp0 · Last edited $date $time';
  }

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
  String get selectPhotosTitle => 'Choose one photo';

  @override
  String get selectPhotos => 'Choose a photo';

  @override
  String get photoLoadFailed => 'This photo cannot be opened';

  @override
  String get compositionPreviewUnavailable =>
      'Composition preview is temporarily unavailable. Reset composition or try again.';

  @override
  String get effectPreviewUnavailable =>
      'This effect preview is temporarily unavailable. Reset the adjustment or try again.';

  @override
  String get photoImportCanceled => 'No photos were added';

  @override
  String get importingPhotos => 'Importing photos…';

  @override
  String get preparingPhoto => 'Preparing photo…';

  @override
  String get restoringProject => 'Restoring your project…';

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
  String get photoLimitReached => 'This project already has a photo';

  @override
  String get projectRestoreFailed =>
      'Your previous project could not be restored';

  @override
  String get projectSaveFailed =>
      'This adjustment could not be saved. Try again.';

  @override
  String get editSavePending => 'Saving this adjustment';

  @override
  String get editSaveRecoveryMessage =>
      'This adjustment is not saved. The last safe result is still shown.';

  @override
  String get discardAdjustment => 'Discard adjustment';

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
  String get qualityImprovement => 'Quality improvement';

  @override
  String get applyQualityImprovement => 'Improve quality';

  @override
  String get noiseReduction => 'Noise reduction';

  @override
  String get lowLightRecovery => 'Low-light recovery';

  @override
  String get hazeRemoval => 'Dehaze';

  @override
  String get detailSharpening => 'Detail sharpening';

  @override
  String get qualityTools => 'Quality';

  @override
  String get naturalPortraitRetouch => 'Natural retouch';

  @override
  String get oneTapNaturalBeautification => 'One-tap natural beautification';

  @override
  String get applyNaturalBeautification => 'Natural beautification';

  @override
  String get textureSmoothing => 'Texture smoothing';

  @override
  String get skinToneLighting => 'Skin tone & face lighting';

  @override
  String get blemishReduction => 'Blemish reduction';

  @override
  String get faceSlim => 'Face slim';

  @override
  String get faceSlimBackgroundProtected =>
      'Face slimming is unavailable for this photo to protect background lines';

  @override
  String get faceSlimMultipleFaces =>
      'Multiple faces detected. Choose the person to adjust.';

  @override
  String get faceSlimUnavailable =>
      'This photo does not currently meet safe face-slimming conditions';

  @override
  String get faceSlimTargetHint => 'Choose a face to adjust (left to right)';

  @override
  String faceSlimTarget(int number) {
    return 'Face $number';
  }

  @override
  String get bodySlim => 'Body slim';

  @override
  String get headSize => 'Smaller head';

  @override
  String get jaw => 'Jaw';

  @override
  String get chin => 'Chin';

  @override
  String get eyes => 'Eyes';

  @override
  String get nose => 'Nose';

  @override
  String get mouth => 'Mouth';

  @override
  String get heightAdjustment => 'Height';

  @override
  String get shoulders => 'Shoulders';

  @override
  String get waist => 'Waist';

  @override
  String get legs => 'Long legs';

  @override
  String get bodyTargetHint => 'Choose a person to adjust (left to right)';

  @override
  String bodyTarget(int number) {
    return 'Person $number';
  }

  @override
  String get semanticTools => 'Background';

  @override
  String get mobileToolRetouch => 'Portrait';

  @override
  String get semanticToolsLocalReady => 'Background adjustments available';

  @override
  String get refineSubjectMask => 'Refine subject edges';

  @override
  String get subjectMask => 'Subject mask';

  @override
  String get localAdjustment => 'Local light & color';

  @override
  String get localExposure => 'Local exposure';

  @override
  String get localSaturation => 'Local saturation';

  @override
  String get paintMask => 'Paint';

  @override
  String get eraseMask => 'Erase';

  @override
  String get maskBrushHint =>
      'Paint where the effect should apply. Switch to Erase to restore an area. Green adds; red removes.';

  @override
  String get clearMask => 'Clear mask';

  @override
  String get semanticSubjectUnavailable =>
      'No supported subject found. The erase brush remains available.';

  @override
  String get backgroundTreatment => 'Background';

  @override
  String get backgroundOriginal => 'Original';

  @override
  String get backgroundBlur => 'Background blur';

  @override
  String get backgroundWhite => 'White background';

  @override
  String get backgroundBlack => 'Black background';

  @override
  String get backgroundWarm => 'Warm background';

  @override
  String get backgroundCool => 'Cool background';

  @override
  String get backgroundImage => 'Photo background';

  @override
  String get backgroundImageImportFailed =>
      'That background photo could not be imported. Try another one.';

  @override
  String get subjectExposure => 'Subject light';

  @override
  String get subjectSaturation => 'Subject saturation';

  @override
  String get backgroundExposure => 'Background light';

  @override
  String get backgroundSaturation => 'Background saturation';

  @override
  String get eraseBrush => 'Erase brush';

  @override
  String get eraseBrushHint =>
      'Paint over an unwanted area to repair it with nearby texture.';

  @override
  String get brushSize => 'Brush size';

  @override
  String get clearEraseStrokes => 'Clear all erase strokes';

  @override
  String get clear => 'Clear';

  @override
  String get apply => 'Apply';

  @override
  String get portraitTools => 'Portrait';

  @override
  String get lightAndColorTools => 'Light';

  @override
  String get localPortraitReady => 'Portrait adjustments available';

  @override
  String get portraitToolsUnavailable =>
      'This photo did not pass portrait safety checks. Light and color tools remain available.';

  @override
  String get resetCurrentAdjustment => 'Reset current adjustment';

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
  String get freeCrop => 'Free crop';

  @override
  String get freeCropHint => 'Drag a crop corner to keep the frame you want';

  @override
  String get applyCrop => 'Apply crop';

  @override
  String get cropFourThree => '4:3';

  @override
  String get cropThreeFour => '3:4';

  @override
  String get cropSixteenNine => '16:9';

  @override
  String get cropNineSixteen => '9:16';

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

  @override
  String get photoStatusUnprocessed => 'Not processed';

  @override
  String get photoStatusAutoCompensated => 'Auto adjusted';

  @override
  String get photoStatusOverridden => 'Photo refined';

  @override
  String get photoStatusFailed => 'Processing failed';

  @override
  String get photoStatusQueued => 'Ready to export';

  @override
  String get photoStatusExporting => 'Exporting';

  @override
  String get photoStatusExported => 'Exported';

  @override
  String get photoStatusExportFailed => 'Export failed';

  @override
  String get photoStatusExportCancelled => 'Export cancelled';

  @override
  String get exportPhotoPlan => 'Photos in this export';

  @override
  String get exportWillExport => 'Will export';

  @override
  String get exportWithSafeFallback => 'Will export with safe fallback';

  @override
  String get exportProcessingEstimate =>
      'Photos are processed locally one at a time. Items not started can be cancelled.';

  @override
  String get startExport => 'Start export';

  @override
  String get exportFormat => 'Format';

  @override
  String get exportFormatJpeg => 'JPEG';

  @override
  String get exportFormatHeif => 'HEIF';

  @override
  String get exportSize => 'Output size';

  @override
  String get exportSizeOriginal => 'Original pixel size';

  @override
  String get exportQuality => 'Quality';

  @override
  String get exportQualityHigh => 'High quality';

  @override
  String get exportQualityStandard => 'Standard';

  @override
  String get exportQualityCompact => 'Save space';

  @override
  String get exportColorSpaceNotice =>
      'The first release exports sRGB and never overwrites the original.';

  @override
  String get exportingPhotos => 'Exporting one photo at a time…';

  @override
  String get cancelExport => 'Cancel items not started';

  @override
  String exportSummary(int saved, int failed, int cancelled) {
    return 'Saved $saved · Failed $failed · Cancelled $cancelled';
  }

  @override
  String get retryFailedPhotos => 'Retry failed and cancelled';

  @override
  String get shareSavedPhotos => 'Share saved photos';

  @override
  String get sharingPhotos => 'Opening system share…';

  @override
  String get photoShareCompleted => 'Shared from the system share sheet';

  @override
  String get photoShareCanceled =>
      'Sharing canceled. The final photo is still saved in Photos.';

  @override
  String get photoShareFailed =>
      'Sharing is unavailable. The final photo is still saved in Photos.';

  @override
  String get continueEditing => 'Continue editing';

  @override
  String get flipHorizontal => 'Flip horizontal';

  @override
  String get flipVertical => 'Flip vertical';

  @override
  String get perspectiveHorizontal => 'Horizontal perspective';

  @override
  String get perspectiveVertical => 'Vertical perspective';

  @override
  String get filterAndHsl => 'Color';

  @override
  String get filterStrength => 'Filter strength';

  @override
  String get hslHue => 'Hue';

  @override
  String get hslSaturation => 'Saturation';

  @override
  String get hslLightness => 'Lightness';

  @override
  String get hslRed => 'Red';

  @override
  String get hslOrange => 'Orange';

  @override
  String get hslYellow => 'Yellow';

  @override
  String get hslGreen => 'Green';

  @override
  String get hslCyan => 'Cyan';

  @override
  String get hslBlue => 'Blue';

  @override
  String get hslPurple => 'Purple';

  @override
  String get hslMagenta => 'Magenta';

  @override
  String get filterNone => 'Original';

  @override
  String get filterClean => 'Clean';

  @override
  String get filterPortrait => 'Portrait';

  @override
  String get filterCinematic => 'Cinematic';

  @override
  String get filterFilm => 'Film';

  @override
  String get filterWarmSun => 'Warm sun';

  @override
  String get filterCoolAir => 'Cool air';

  @override
  String get filterVivid => 'Vivid';

  @override
  String get filterFaded => 'Faded';

  @override
  String get filterNoir => 'Noir';

  @override
  String get filterFood => 'Food';

  @override
  String get filterLandscape => 'Landscape';

  @override
  String get filterNight => 'Night';

  @override
  String get voiceEditEntry => 'Tell me how to edit';

  @override
  String get voiceEditPrompt => 'What else would you like to change?';

  @override
  String get quickNatural => 'More natural';

  @override
  String get quickBrighten => 'Brighter';

  @override
  String get quickAtmosphere => 'Atmosphere';

  @override
  String get quickEditBrighter => 'Make it brighter';

  @override
  String get quickEditNaturalSkin => 'Natural skin';

  @override
  String get quickEditAtmosphere => 'Add more atmosphere';

  @override
  String get quickEditSoftBackground => 'Soften the background';

  @override
  String get onlyEditThisPhoto => 'Only this photo';

  @override
  String get syncToAllPhotos => 'Sync to all';

  @override
  String get manualAdjustments => 'Manual adjustments';

  @override
  String get manualAdjustmentsHint =>
      'Open all parameters only when you need them';

  @override
  String get adjustPhoto => 'Adjust myself';

  @override
  String get quickAdjust => 'Quick adjustments';

  @override
  String get allTools => 'More';

  @override
  String get metaOpSearchHint => 'Search adjustments';

  @override
  String get metaOpSearchNoResults => 'No available adjustment found';

  @override
  String get savePhotos => 'Export';

  @override
  String get preparingExport => 'Preparing final photo…';

  @override
  String get canvasInteractionHint =>
      'Tap for full screen · Hold to view original';

  @override
  String get savingToSystemPhotos => 'Saving to Photos…';

  @override
  String get savedToSystemPhotos => 'Saved to Photos';

  @override
  String get exportFailedTitle => 'Could not export';

  @override
  String get photoPermissionPurpose =>
      'Yingjian needs add-only photo access to save the final photo to Photos.';

  @override
  String get goToSystemSettings => 'Open Settings';

  @override
  String get saveOptionsTitle => 'Ready to save';

  @override
  String get saveOptionsSubtitle => 'Choose which photos to save';

  @override
  String get saveToAlbum => 'Save to Photos';

  @override
  String savingProgress(int current, int total) {
    return 'Saving $current/$total';
  }

  @override
  String photoNumber(int number) {
    return 'Photo $number';
  }

  @override
  String get cancelRemainingPhotos => 'Cancel remaining photos';

  @override
  String get savedPhotosAreKept => 'Photos already saved will be kept';

  @override
  String partialSaveTitle(int saved, int failed) {
    return 'Saved $saved; $failed could not be saved yet';
  }

  @override
  String get photoLibraryTemporarilyUnavailable =>
      'The photo library is temporarily unavailable';

  @override
  String retryPhotoCount(int count) {
    return 'Retry these $count';
  }

  @override
  String get viewSavedPhotos => 'View saved photos';

  @override
  String get backToEditing => 'Back to editing';

  @override
  String get voiceEditTitle => 'What would you like to change?';

  @override
  String get voiceEditHint => 'For example: make it brighter with natural skin';

  @override
  String get voiceEditRecord => 'Start speaking';

  @override
  String get voiceEditStop => 'Finish recording';

  @override
  String get voiceEditListening => 'Listening…';

  @override
  String get voiceEditApply => 'Apply changes';

  @override
  String get voiceEditUnsupported =>
      'This instruction cannot be interpreted safely yet. Try different wording or adjust it manually.';

  @override
  String get voiceEditFailed =>
      'Voice is temporarily unavailable. You can type the instruction instead.';

  @override
  String voiceEditApplied(int count) {
    return 'Applied $count visible parameters';
  }

  @override
  String get voiceEditDone => 'Done';

  @override
  String get editResultBrighter => 'Made this photo brighter';

  @override
  String get editResultApplied => 'Change applied';

  @override
  String get editApplied => 'Applied';

  @override
  String get manualSimpleHint => 'Choose the result you want';

  @override
  String get manualBrighter => 'Brighter';

  @override
  String get manualWarmer => 'Warmer';

  @override
  String get manualMoreVivid => 'More vivid';

  @override
  String get manualNaturalSkin => 'Natural skin';

  @override
  String get manualSmootherSkin => 'Smoother skin';

  @override
  String get manualSmallerFace => 'Smaller face';

  @override
  String get manualNaturalBody => 'Natural body';

  @override
  String get choosePersonTitle => 'Who would you like to edit?';

  @override
  String get choosePersonHint => 'Tap a person in the photo';

  @override
  String saveSuccess(int count) {
    return 'Saved $count photos';
  }

  @override
  String get finish => 'Done';

  @override
  String get close => 'Close';

  @override
  String get fullscreenPreview => 'View full screen';

  @override
  String get fullscreenAdjusted => 'Edited';

  @override
  String get fullscreenPreviewHint => 'Tap to return · Hold for original';

  @override
  String get projectRequiresUpdateTitle => 'Update to continue editing';

  @override
  String get projectRequiresUpdateMessage =>
      'This project contains effects this version cannot handle. Everything is preserved and view-only until the app is updated.';

  @override
  String get visualTracksTitle => 'Visual Tracks';

  @override
  String get visualTracksEntry => 'Visual Tracks';

  @override
  String get visualTracksNotApplied => 'This change was not applied';

  @override
  String get eraAtmosphereTrack => 'Era atmosphere';

  @override
  String get lightingTrack => 'Lighting';

  @override
  String get vintageFilm => 'Vintage film';

  @override
  String get currentEffect => 'Current look';

  @override
  String get nearFuture => 'Near future';

  @override
  String get lightingNeedsPerson =>
      'No person in this photo can be relit safely';

  @override
  String personNumber(int number) {
    return 'Person $number';
  }

  @override
  String get leftLight => 'Left light';

  @override
  String get frontLight => 'Front light';

  @override
  String get rightLight => 'Right light';
}
