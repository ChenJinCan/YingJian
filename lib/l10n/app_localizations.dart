import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// 应用名称
  ///
  /// In zh, this message translates to:
  /// **'映见'**
  String get appTitle;

  /// 首页核心价值主张
  ///
  /// In zh, this message translates to:
  /// **'一张精修，整组好看'**
  String get homeTagline;

  /// No description provided for @startEditing.
  ///
  /// In zh, this message translates to:
  /// **'开始修图'**
  String get startEditing;

  /// No description provided for @unfinishedProject.
  ///
  /// In zh, this message translates to:
  /// **'未完成项目'**
  String get unfinishedProject;

  /// No description provided for @continueLastEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续上次编辑'**
  String get continueLastEditing;

  /// No description provided for @startNewProject.
  ///
  /// In zh, this message translates to:
  /// **'开始新项目'**
  String get startNewProject;

  /// No description provided for @deleteAndStartNew.
  ///
  /// In zh, this message translates to:
  /// **'删除并新建'**
  String get deleteAndStartNew;

  /// No description provided for @projectDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法删除本地项目，现有内容未改变。'**
  String get projectDeleteFailed;

  /// No description provided for @lastProjectSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张照片 · 最后编辑于 {date} {time}'**
  String lastProjectSummary(int count, String date, String time);

  /// No description provided for @editorTitle.
  ///
  /// In zh, this message translates to:
  /// **'精修工作台'**
  String get editorTitle;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get redo;

  /// No description provided for @reset.
  ///
  /// In zh, this message translates to:
  /// **'重置'**
  String get reset;

  /// No description provided for @photoPreviewArea.
  ///
  /// In zh, this message translates to:
  /// **'照片预览区域'**
  String get photoPreviewArea;

  /// No description provided for @selectPhotosTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择 1–6 张照片'**
  String get selectPhotosTitle;

  /// No description provided for @selectPhotos.
  ///
  /// In zh, this message translates to:
  /// **'选择照片'**
  String get selectPhotos;

  /// No description provided for @addPhotos.
  ///
  /// In zh, this message translates to:
  /// **'继续添加照片'**
  String get addPhotos;

  /// No description provided for @photoImportPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'照片仅复制到映见的本地项目中，不会因选择照片而上传云端。'**
  String get photoImportPrivacy;

  /// No description provided for @photoCount.
  ///
  /// In zh, this message translates to:
  /// **'{count}/6'**
  String photoCount(int count);

  /// No description provided for @photoLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取这张照片'**
  String get photoLoadFailed;

  /// No description provided for @compositionPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'构图预览暂不可用。可恢复原始构图或稍后重试；原图不受影响。'**
  String get compositionPreviewUnavailable;

  /// No description provided for @effectPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前效果预览暂不可用。可重置本次调整或稍后重试；原图不受影响。'**
  String get effectPreviewUnavailable;

  /// No description provided for @recommendationPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这套推荐预览暂不可用。可重试或查看其他方向；原图不受影响。'**
  String get recommendationPreviewUnavailable;

  /// No description provided for @photoImportCanceled.
  ///
  /// In zh, this message translates to:
  /// **'未添加任何照片'**
  String get photoImportCanceled;

  /// No description provided for @importingPhotos.
  ///
  /// In zh, this message translates to:
  /// **'正在本地导入照片…'**
  String get importingPhotos;

  /// No description provided for @restoringProject.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复本地项目…'**
  String get restoringProject;

  /// No description provided for @photoImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'照片导入失败，请重试'**
  String get photoImportFailed;

  /// No description provided for @photoImportIssuesTitle.
  ///
  /// In zh, this message translates to:
  /// **'部分照片未导入'**
  String get photoImportIssuesTitle;

  /// No description provided for @photoUnsupportedFormat.
  ///
  /// In zh, this message translates to:
  /// **'{name}：格式暂不支持'**
  String photoUnsupportedFormat(String name);

  /// No description provided for @photoAnimatedUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'{name}：暂不支持动态图片'**
  String photoAnimatedUnsupported(String name);

  /// No description provided for @photoFileTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'{name}：文件超过 100 MB'**
  String photoFileTooLarge(String name);

  /// No description provided for @photoDimensionsTooLarge.
  ///
  /// In zh, this message translates to:
  /// **'{name}：超过 48 MP 或最长边 12,000 px'**
  String photoDimensionsTooLarge(String name);

  /// No description provided for @photoUnreadable.
  ///
  /// In zh, this message translates to:
  /// **'{name}：图片损坏或无法读取'**
  String photoUnreadable(String name);

  /// No description provided for @photoCopyFailed.
  ///
  /// In zh, this message translates to:
  /// **'{name}：无法创建本地工作副本'**
  String photoCopyFailed(String name);

  /// No description provided for @photoLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'每个项目最多导入 6 张照片'**
  String get photoLimitReached;

  /// No description provided for @projectRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法恢复上次项目'**
  String get projectRestoreFailed;

  /// No description provided for @projectSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存本次调整，请重试'**
  String get projectSaveFailed;

  /// No description provided for @removePhoto.
  ///
  /// In zh, this message translates to:
  /// **'移除照片'**
  String get removePhoto;

  /// No description provided for @removePhotoConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'仅删除映见项目中的本地副本，不影响系统相册原图。'**
  String get removePhotoConfirmation;

  /// No description provided for @deleteProject.
  ///
  /// In zh, this message translates to:
  /// **'删除项目'**
  String get deleteProject;

  /// No description provided for @deleteProjectConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'删除项目和映见保存的工作副本？系统相册原图不会被删除。'**
  String get deleteProjectConfirmation;

  /// No description provided for @movePhotoEarlier.
  ///
  /// In zh, this message translates to:
  /// **'向前移动'**
  String get movePhotoEarlier;

  /// No description provided for @movePhotoLater.
  ///
  /// In zh, this message translates to:
  /// **'向后移动'**
  String get movePhotoLater;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @exposure.
  ///
  /// In zh, this message translates to:
  /// **'曝光'**
  String get exposure;

  /// No description provided for @highlights.
  ///
  /// In zh, this message translates to:
  /// **'高光'**
  String get highlights;

  /// No description provided for @shadows.
  ///
  /// In zh, this message translates to:
  /// **'阴影'**
  String get shadows;

  /// No description provided for @contrast.
  ///
  /// In zh, this message translates to:
  /// **'对比度'**
  String get contrast;

  /// No description provided for @warmth.
  ///
  /// In zh, this message translates to:
  /// **'色温'**
  String get warmth;

  /// No description provided for @tint.
  ///
  /// In zh, this message translates to:
  /// **'色调'**
  String get tint;

  /// No description provided for @saturation.
  ///
  /// In zh, this message translates to:
  /// **'饱和度'**
  String get saturation;

  /// No description provided for @clarity.
  ///
  /// In zh, this message translates to:
  /// **'清晰度'**
  String get clarity;

  /// No description provided for @qualityImprovement.
  ///
  /// In zh, this message translates to:
  /// **'画质改善'**
  String get qualityImprovement;

  /// No description provided for @applyQualityImprovement.
  ///
  /// In zh, this message translates to:
  /// **'一键改善画质'**
  String get applyQualityImprovement;

  /// No description provided for @noiseReduction.
  ///
  /// In zh, this message translates to:
  /// **'去噪'**
  String get noiseReduction;

  /// No description provided for @lowLightRecovery.
  ///
  /// In zh, this message translates to:
  /// **'暗光提亮'**
  String get lowLightRecovery;

  /// No description provided for @hazeRemoval.
  ///
  /// In zh, this message translates to:
  /// **'去灰'**
  String get hazeRemoval;

  /// No description provided for @detailSharpening.
  ///
  /// In zh, this message translates to:
  /// **'细节锐化'**
  String get detailSharpening;

  /// No description provided for @qualityTools.
  ///
  /// In zh, this message translates to:
  /// **'画质'**
  String get qualityTools;

  /// No description provided for @naturalPortraitRetouch.
  ///
  /// In zh, this message translates to:
  /// **'自然精修'**
  String get naturalPortraitRetouch;

  /// No description provided for @oneTapNaturalBeautification.
  ///
  /// In zh, this message translates to:
  /// **'一键自然美化'**
  String get oneTapNaturalBeautification;

  /// No description provided for @applyNaturalBeautification.
  ///
  /// In zh, this message translates to:
  /// **'应用自然美化'**
  String get applyNaturalBeautification;

  /// No description provided for @textureSmoothing.
  ///
  /// In zh, this message translates to:
  /// **'质感磨皮'**
  String get textureSmoothing;

  /// No description provided for @skinToneLighting.
  ///
  /// In zh, this message translates to:
  /// **'肤色与面部光线'**
  String get skinToneLighting;

  /// No description provided for @blemishReduction.
  ///
  /// In zh, this message translates to:
  /// **'瑕疵减弱'**
  String get blemishReduction;

  /// No description provided for @faceSlim.
  ///
  /// In zh, this message translates to:
  /// **'瘦脸'**
  String get faceSlim;

  /// No description provided for @faceSlimBackgroundProtected.
  ///
  /// In zh, this message translates to:
  /// **'为保护背景线条，这张照片暂不提供瘦脸'**
  String get faceSlimBackgroundProtected;

  /// No description provided for @faceSlimMultipleFaces.
  ///
  /// In zh, this message translates to:
  /// **'检测到多个人脸：自然精修可用，瘦脸仅支持单人照片'**
  String get faceSlimMultipleFaces;

  /// No description provided for @faceSlimUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这张照片暂不满足安全瘦脸条件'**
  String get faceSlimUnavailable;

  /// No description provided for @faceSlimTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'选择要调整的人脸（按画面从左到右）'**
  String get faceSlimTargetHint;

  /// No description provided for @faceSlimTarget.
  ///
  /// In zh, this message translates to:
  /// **'人脸 {number}'**
  String faceSlimTarget(int number);

  /// No description provided for @bodySlim.
  ///
  /// In zh, this message translates to:
  /// **'瘦身'**
  String get bodySlim;

  /// No description provided for @portraitTools.
  ///
  /// In zh, this message translates to:
  /// **'人像'**
  String get portraitTools;

  /// No description provided for @lightAndColorTools.
  ///
  /// In zh, this message translates to:
  /// **'光色'**
  String get lightAndColorTools;

  /// No description provided for @localPortraitReady.
  ///
  /// In zh, this message translates to:
  /// **'人像工具已就绪 · 本地处理'**
  String get localPortraitReady;

  /// No description provided for @portraitToolsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前照片未通过人像安全检测，仍可继续调整光色'**
  String get portraitToolsUnavailable;

  /// No description provided for @switchToCurrentPhotoForPortrait.
  ///
  /// In zh, this message translates to:
  /// **'切换到“当前照片”后可使用人像工具'**
  String get switchToCurrentPhotoForPortrait;

  /// No description provided for @resetCurrentAdjustment.
  ///
  /// In zh, this message translates to:
  /// **'归零当前调整'**
  String get resetCurrentAdjustment;

  /// No description provided for @composition.
  ///
  /// In zh, this message translates to:
  /// **'构图'**
  String get composition;

  /// No description provided for @straighten.
  ///
  /// In zh, this message translates to:
  /// **'水平校正'**
  String get straighten;

  /// No description provided for @rotateLeft.
  ///
  /// In zh, this message translates to:
  /// **'向左旋转'**
  String get rotateLeft;

  /// No description provided for @rotateRight.
  ///
  /// In zh, this message translates to:
  /// **'向右旋转'**
  String get rotateRight;

  /// No description provided for @originalCrop.
  ///
  /// In zh, this message translates to:
  /// **'原始'**
  String get originalCrop;

  /// No description provided for @cropSquare.
  ///
  /// In zh, this message translates to:
  /// **'1:1'**
  String get cropSquare;

  /// No description provided for @cropFourThree.
  ///
  /// In zh, this message translates to:
  /// **'4:3'**
  String get cropFourThree;

  /// No description provided for @cropSixteenNine.
  ///
  /// In zh, this message translates to:
  /// **'16:9'**
  String get cropSixteenNine;

  /// No description provided for @resetComposition.
  ///
  /// In zh, this message translates to:
  /// **'恢复原始构图'**
  String get resetComposition;

  /// No description provided for @compareOriginal.
  ///
  /// In zh, this message translates to:
  /// **'查看原图'**
  String get compareOriginal;

  /// No description provided for @compareEdited.
  ///
  /// In zh, this message translates to:
  /// **'返回效果'**
  String get compareEdited;

  /// No description provided for @exportOriginalQuality.
  ///
  /// In zh, this message translates to:
  /// **'原画质导出'**
  String get exportOriginalQuality;

  /// No description provided for @photoExported.
  ///
  /// In zh, this message translates to:
  /// **'已保存到系统相册（{width} × {height}）'**
  String photoExported(int width, int height);

  /// No description provided for @photoExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败，请检查相册权限后重试'**
  String get photoExportFailed;

  /// No description provided for @unknownPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'页面不存在'**
  String get unknownPageTitle;

  /// No description provided for @unknownPageMessage.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法打开这个页面'**
  String get unknownPageMessage;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @privacyAndDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'隐私与诊断'**
  String get privacyAndDiagnostics;

  /// No description provided for @anonymousDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'匿名诊断'**
  String get anonymousDiagnostics;

  /// No description provided for @diagnosticsOffDescription.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭，不发送分析、崩溃或性能数据'**
  String get diagnosticsOffDescription;

  /// No description provided for @diagnosticsOnDescription.
  ///
  /// In zh, this message translates to:
  /// **'发送经过最小化处理的匿名诊断数据'**
  String get diagnosticsOnDescription;

  /// No description provided for @diagnosticsUnavailableDescription.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置映见独立 Firebase 项目'**
  String get diagnosticsUnavailableDescription;

  /// No description provided for @diagnosticsEnableFailed.
  ///
  /// In zh, this message translates to:
  /// **'诊断服务暂不可用，设置已保持关闭'**
  String get diagnosticsEnableFailed;

  /// No description provided for @privacyPolicy.
  ///
  /// In zh, this message translates to:
  /// **'隐私政策'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicyDescription.
  ///
  /// In zh, this message translates to:
  /// **'查看照片、诊断与第三方数据处理说明'**
  String get privacyPolicyDescription;

  /// No description provided for @termsOfUse.
  ///
  /// In zh, this message translates to:
  /// **'使用条款'**
  String get termsOfUse;

  /// No description provided for @rateApp.
  ///
  /// In zh, this message translates to:
  /// **'去评分'**
  String get rateApp;

  /// No description provided for @rateAppDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开应用商店评分页面'**
  String get rateAppDescription;

  /// No description provided for @storeListingUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'应用商店页面尚未配置'**
  String get storeListingUnavailable;

  /// No description provided for @openSourceLicenses.
  ///
  /// In zh, this message translates to:
  /// **'开源许可'**
  String get openSourceLicenses;

  /// No description provided for @legalDocumentLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法加载此文档'**
  String get legalDocumentLoadFailed;

  /// No description provided for @analysisPreparing.
  ///
  /// In zh, this message translates to:
  /// **'正在本地准备三套效果…'**
  String get analysisPreparing;

  /// No description provided for @recommendationsTitle.
  ///
  /// In zh, this message translates to:
  /// **'先选一个整体方向'**
  String get recommendationsTitle;

  /// No description provided for @recommendationsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'三套效果都在本机生成，不上传照片。选中后可继续细调。'**
  String get recommendationsSubtitle;

  /// No description provided for @safeFallbackNotice.
  ///
  /// In zh, this message translates to:
  /// **'当前使用克制的安全配方；像素级分析能力完成质量验证后再启用。'**
  String get safeFallbackNotice;

  /// No description provided for @localAnalysisNotice.
  ///
  /// In zh, this message translates to:
  /// **'本机像素分析已为每张照片准备有边界的自适应调整。'**
  String get localAnalysisNotice;

  /// No description provided for @localEffect.
  ///
  /// In zh, this message translates to:
  /// **'本地效果'**
  String get localEffect;

  /// No description provided for @useThisLook.
  ///
  /// In zh, this message translates to:
  /// **'使用这套效果'**
  String get useThisLook;

  /// No description provided for @recommendationNaturalClean.
  ///
  /// In zh, this message translates to:
  /// **'自然干净'**
  String get recommendationNaturalClean;

  /// No description provided for @recommendationAtmosphericColor.
  ///
  /// In zh, this message translates to:
  /// **'氛围色彩'**
  String get recommendationAtmosphericColor;

  /// No description provided for @recommendationTexturedStyle.
  ///
  /// In zh, this message translates to:
  /// **'质感风格'**
  String get recommendationTexturedStyle;

  /// No description provided for @recommendationReasonBalancedFallback.
  ///
  /// In zh, this message translates to:
  /// **'均衡克制的安全回退'**
  String get recommendationReasonBalancedFallback;

  /// No description provided for @recommendationReasonWarmFallback.
  ///
  /// In zh, this message translates to:
  /// **'安全增加轻微暖意'**
  String get recommendationReasonWarmFallback;

  /// No description provided for @recommendationReasonTexturedFallback.
  ///
  /// In zh, this message translates to:
  /// **'克制增强质感，不激进锐化'**
  String get recommendationReasonTexturedFallback;

  /// No description provided for @recommendationReasonProtectsUncertain.
  ///
  /// In zh, this message translates to:
  /// **'保守保护不确定输入'**
  String get recommendationReasonProtectsUncertain;

  /// No description provided for @recommendationReasonProtectsTexture.
  ///
  /// In zh, this message translates to:
  /// **'保留细节与局部反差'**
  String get recommendationReasonProtectsTexture;

  /// No description provided for @recommendationReasonCorrectsExposure.
  ///
  /// In zh, this message translates to:
  /// **'平衡检测到的曝光'**
  String get recommendationReasonCorrectsExposure;

  /// No description provided for @recommendationReasonCorrectsWhiteBalance.
  ///
  /// In zh, this message translates to:
  /// **'修正检测到的偏色'**
  String get recommendationReasonCorrectsWhiteBalance;

  /// No description provided for @editWholeGroup.
  ///
  /// In zh, this message translates to:
  /// **'编辑整组'**
  String get editWholeGroup;

  /// No description provided for @editCurrentPhoto.
  ///
  /// In zh, this message translates to:
  /// **'仅当前照片'**
  String get editCurrentPhoto;

  /// No description provided for @photoPositionAndScope.
  ///
  /// In zh, this message translates to:
  /// **'第 {current} / {total} 张 · {scope}'**
  String photoPositionAndScope(int current, int total, String scope);

  /// No description provided for @photoStatusUnprocessed.
  ///
  /// In zh, this message translates to:
  /// **'未处理'**
  String get photoStatusUnprocessed;

  /// No description provided for @photoStatusAutoCompensated.
  ///
  /// In zh, this message translates to:
  /// **'自动补偿'**
  String get photoStatusAutoCompensated;

  /// No description provided for @photoStatusOverridden.
  ///
  /// In zh, this message translates to:
  /// **'单张精修'**
  String get photoStatusOverridden;

  /// No description provided for @photoStatusFailed.
  ///
  /// In zh, this message translates to:
  /// **'处理失败'**
  String get photoStatusFailed;

  /// No description provided for @photoStatusQueued.
  ///
  /// In zh, this message translates to:
  /// **'待导出'**
  String get photoStatusQueued;

  /// No description provided for @batchExportPhotos.
  ///
  /// In zh, this message translates to:
  /// **'批量导出 {count} 张'**
  String batchExportPhotos(int count);

  /// No description provided for @exportConfirmationMessage.
  ///
  /// In zh, this message translates to:
  /// **'将从每张只读原图生成 JPEG（sRGB，质量 95），共 {count} 张，并保存到系统相册。'**
  String exportConfirmationMessage(int count);

  /// No description provided for @startExport.
  ///
  /// In zh, this message translates to:
  /// **'开始导出'**
  String get startExport;

  /// No description provided for @syncCurrentAdjustments.
  ///
  /// In zh, this message translates to:
  /// **'同步当前调整到整组'**
  String get syncCurrentAdjustments;

  /// No description provided for @syncGroupConfirmationTitle.
  ///
  /// In zh, this message translates to:
  /// **'将当前光色调整同步到整组？'**
  String get syncGroupConfirmationTitle;

  /// No description provided for @syncGroupConfirmationMessage.
  ///
  /// In zh, this message translates to:
  /// **'曝光、色彩和质感会应用到全部照片；构图仍只保留在当前照片。这个操作可以撤销。'**
  String get syncGroupConfirmationMessage;

  /// No description provided for @syncGroupAction.
  ///
  /// In zh, this message translates to:
  /// **'同步整组'**
  String get syncGroupAction;

  /// No description provided for @exportingPhotos.
  ///
  /// In zh, this message translates to:
  /// **'正在逐张导出…'**
  String get exportingPhotos;

  /// No description provided for @cancelExport.
  ///
  /// In zh, this message translates to:
  /// **'取消未开始项'**
  String get cancelExport;

  /// No description provided for @exportSummary.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {saved} 张 · 失败 {failed} 张 · 取消 {cancelled} 张'**
  String exportSummary(int saved, int failed, int cancelled);

  /// No description provided for @retryFailedPhotos.
  ///
  /// In zh, this message translates to:
  /// **'只重试失败与取消项'**
  String get retryFailedPhotos;

  /// No description provided for @shareSavedPhotos.
  ///
  /// In zh, this message translates to:
  /// **'分享已保存照片'**
  String get shareSavedPhotos;

  /// No description provided for @sharingPhotos.
  ///
  /// In zh, this message translates to:
  /// **'正在打开系统分享…'**
  String get sharingPhotos;

  /// No description provided for @photoShareCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已通过系统分享完成操作'**
  String get photoShareCompleted;

  /// No description provided for @photoShareCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消分享，保存结果不受影响'**
  String get photoShareCanceled;

  /// No description provided for @photoShareFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法分享，保存结果不受影响'**
  String get photoShareFailed;

  /// No description provided for @continueEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get continueEditing;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
