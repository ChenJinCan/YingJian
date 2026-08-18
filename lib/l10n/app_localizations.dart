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

  /// No description provided for @homeHeroTitle.
  ///
  /// In zh, this message translates to:
  /// **'让变美更容易'**
  String get homeHeroTitle;

  /// No description provided for @recentProjects.
  ///
  /// In zh, this message translates to:
  /// **'最近项目'**
  String get recentProjects;

  /// No description provided for @noRecentProjects.
  ///
  /// In zh, this message translates to:
  /// **'还没有项目，选几张照片开始吧'**
  String get noRecentProjects;

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
  /// **'检测到多个人脸，请选择要调整的人物'**
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

  /// No description provided for @headSize.
  ///
  /// In zh, this message translates to:
  /// **'小头'**
  String get headSize;

  /// No description provided for @jaw.
  ///
  /// In zh, this message translates to:
  /// **'下颌'**
  String get jaw;

  /// No description provided for @chin.
  ///
  /// In zh, this message translates to:
  /// **'下巴'**
  String get chin;

  /// No description provided for @eyes.
  ///
  /// In zh, this message translates to:
  /// **'眼睛'**
  String get eyes;

  /// No description provided for @nose.
  ///
  /// In zh, this message translates to:
  /// **'鼻子'**
  String get nose;

  /// No description provided for @mouth.
  ///
  /// In zh, this message translates to:
  /// **'嘴型'**
  String get mouth;

  /// No description provided for @heightAdjustment.
  ///
  /// In zh, this message translates to:
  /// **'增高'**
  String get heightAdjustment;

  /// No description provided for @shoulders.
  ///
  /// In zh, this message translates to:
  /// **'肩宽'**
  String get shoulders;

  /// No description provided for @waist.
  ///
  /// In zh, this message translates to:
  /// **'腰围'**
  String get waist;

  /// No description provided for @legs.
  ///
  /// In zh, this message translates to:
  /// **'长腿'**
  String get legs;

  /// No description provided for @bodyTargetHint.
  ///
  /// In zh, this message translates to:
  /// **'选择要调整的人物（按画面从左到右）'**
  String get bodyTargetHint;

  /// No description provided for @bodyTarget.
  ///
  /// In zh, this message translates to:
  /// **'人物 {number}'**
  String bodyTarget(int number);

  /// No description provided for @semanticTools.
  ///
  /// In zh, this message translates to:
  /// **'主体与局部'**
  String get semanticTools;

  /// No description provided for @mobileToolRetouch.
  ///
  /// In zh, this message translates to:
  /// **'精修'**
  String get mobileToolRetouch;

  /// No description provided for @semanticToolsLocalReady.
  ///
  /// In zh, this message translates to:
  /// **'主体分割已就绪 · 本地处理'**
  String get semanticToolsLocalReady;

  /// No description provided for @refineSubjectMask.
  ///
  /// In zh, this message translates to:
  /// **'修整主体边缘'**
  String get refineSubjectMask;

  /// No description provided for @subjectMask.
  ///
  /// In zh, this message translates to:
  /// **'主体蒙版'**
  String get subjectMask;

  /// No description provided for @localAdjustment.
  ///
  /// In zh, this message translates to:
  /// **'局部光色'**
  String get localAdjustment;

  /// No description provided for @localExposure.
  ///
  /// In zh, this message translates to:
  /// **'局部曝光'**
  String get localExposure;

  /// No description provided for @localSaturation.
  ///
  /// In zh, this message translates to:
  /// **'局部饱和度'**
  String get localSaturation;

  /// No description provided for @paintMask.
  ///
  /// In zh, this message translates to:
  /// **'涂抹'**
  String get paintMask;

  /// No description provided for @eraseMask.
  ///
  /// In zh, this message translates to:
  /// **'擦除'**
  String get eraseMask;

  /// No description provided for @maskBrushHint.
  ///
  /// In zh, this message translates to:
  /// **'在画面上涂抹需要生效的区域；切换擦除可恢复该区域。绿色为添加，红色为擦除。'**
  String get maskBrushHint;

  /// No description provided for @clearMask.
  ///
  /// In zh, this message translates to:
  /// **'清空蒙版'**
  String get clearMask;

  /// No description provided for @semanticSubjectUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'未识别到可用主体；仍可使用消除笔'**
  String get semanticSubjectUnavailable;

  /// No description provided for @backgroundTreatment.
  ///
  /// In zh, this message translates to:
  /// **'背景处理'**
  String get backgroundTreatment;

  /// No description provided for @backgroundOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原背景'**
  String get backgroundOriginal;

  /// No description provided for @backgroundBlur.
  ///
  /// In zh, this message translates to:
  /// **'背景虚化'**
  String get backgroundBlur;

  /// No description provided for @backgroundWhite.
  ///
  /// In zh, this message translates to:
  /// **'白色背景'**
  String get backgroundWhite;

  /// No description provided for @backgroundBlack.
  ///
  /// In zh, this message translates to:
  /// **'黑色背景'**
  String get backgroundBlack;

  /// No description provided for @backgroundWarm.
  ///
  /// In zh, this message translates to:
  /// **'暖色背景'**
  String get backgroundWarm;

  /// No description provided for @backgroundCool.
  ///
  /// In zh, this message translates to:
  /// **'冷色背景'**
  String get backgroundCool;

  /// No description provided for @backgroundImage.
  ///
  /// In zh, this message translates to:
  /// **'图片背景'**
  String get backgroundImage;

  /// No description provided for @backgroundImageImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'背景图片无法导入，请换一张重试。'**
  String get backgroundImageImportFailed;

  /// No description provided for @subjectExposure.
  ///
  /// In zh, this message translates to:
  /// **'主体明暗'**
  String get subjectExposure;

  /// No description provided for @subjectSaturation.
  ///
  /// In zh, this message translates to:
  /// **'主体饱和'**
  String get subjectSaturation;

  /// No description provided for @backgroundExposure.
  ///
  /// In zh, this message translates to:
  /// **'背景明暗'**
  String get backgroundExposure;

  /// No description provided for @backgroundSaturation.
  ///
  /// In zh, this message translates to:
  /// **'背景饱和'**
  String get backgroundSaturation;

  /// No description provided for @eraseBrush.
  ///
  /// In zh, this message translates to:
  /// **'消除笔'**
  String get eraseBrush;

  /// No description provided for @eraseBrushHint.
  ///
  /// In zh, this message translates to:
  /// **'在要移除的区域上涂抹；使用周围纹理进行本地修补'**
  String get eraseBrushHint;

  /// No description provided for @brushSize.
  ///
  /// In zh, this message translates to:
  /// **'笔刷大小'**
  String get brushSize;

  /// No description provided for @clearEraseStrokes.
  ///
  /// In zh, this message translates to:
  /// **'清除全部消除笔画'**
  String get clearEraseStrokes;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清除'**
  String get clear;

  /// No description provided for @apply.
  ///
  /// In zh, this message translates to:
  /// **'应用'**
  String get apply;

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

  /// No description provided for @groupStyleIntensity.
  ///
  /// In zh, this message translates to:
  /// **'整组风格'**
  String get groupStyleIntensity;

  /// No description provided for @groupStyleIntensityHint.
  ///
  /// In zh, this message translates to:
  /// **'调整整组共享效果强度，同时保留每张照片的独立补偿。'**
  String get groupStyleIntensityHint;

  /// No description provided for @primaryRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'主推荐'**
  String get primaryRecommendation;

  /// No description provided for @alternativeRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'备选'**
  String get alternativeRecommendation;

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

  /// No description provided for @freeCrop.
  ///
  /// In zh, this message translates to:
  /// **'自由裁剪'**
  String get freeCrop;

  /// No description provided for @freeCropHint.
  ///
  /// In zh, this message translates to:
  /// **'拖动裁剪框的角点，保留想要的画面'**
  String get freeCropHint;

  /// No description provided for @applyCrop.
  ///
  /// In zh, this message translates to:
  /// **'应用裁剪'**
  String get applyCrop;

  /// No description provided for @cropFourThree.
  ///
  /// In zh, this message translates to:
  /// **'4:3'**
  String get cropFourThree;

  /// No description provided for @cropThreeFour.
  ///
  /// In zh, this message translates to:
  /// **'3:4'**
  String get cropThreeFour;

  /// No description provided for @cropSixteenNine.
  ///
  /// In zh, this message translates to:
  /// **'16:9'**
  String get cropSixteenNine;

  /// No description provided for @cropNineSixteen.
  ///
  /// In zh, this message translates to:
  /// **'9:16'**
  String get cropNineSixteen;

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
  /// **'选一个喜欢的方向'**
  String get recommendationsTitle;

  /// No description provided for @recommendationsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'三套效果都在本机生成，不上传照片。先看结果，之后随时都能继续修改。'**
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
  /// **'就用这个'**
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

  /// No description provided for @photoStatusExporting.
  ///
  /// In zh, this message translates to:
  /// **'导出中'**
  String get photoStatusExporting;

  /// No description provided for @photoStatusExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出'**
  String get photoStatusExported;

  /// No description provided for @photoStatusExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败'**
  String get photoStatusExportFailed;

  /// No description provided for @photoStatusExportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'已取消导出'**
  String get photoStatusExportCancelled;

  /// No description provided for @batchExportPhotos.
  ///
  /// In zh, this message translates to:
  /// **'批量导出 {count} 张'**
  String batchExportPhotos(int count);

  /// No description provided for @exportConfirmationMessage.
  ///
  /// In zh, this message translates to:
  /// **'将从 {count} 张只读原图重新执行全部效果并保存到系统相册。'**
  String exportConfirmationMessage(int count);

  /// No description provided for @exportPhotoPlan.
  ///
  /// In zh, this message translates to:
  /// **'本次照片'**
  String get exportPhotoPlan;

  /// No description provided for @exportWillExport.
  ///
  /// In zh, this message translates to:
  /// **'将导出'**
  String get exportWillExport;

  /// No description provided for @exportWithSafeFallback.
  ///
  /// In zh, this message translates to:
  /// **'将以安全回退导出'**
  String get exportWithSafeFallback;

  /// No description provided for @exportProcessingEstimate.
  ///
  /// In zh, this message translates to:
  /// **'预计逐张本地处理，可取消尚未开始的照片。'**
  String get exportProcessingEstimate;

  /// No description provided for @startExport.
  ///
  /// In zh, this message translates to:
  /// **'开始导出'**
  String get startExport;

  /// No description provided for @exportFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式'**
  String get exportFormat;

  /// No description provided for @exportFormatJpeg.
  ///
  /// In zh, this message translates to:
  /// **'JPEG'**
  String get exportFormatJpeg;

  /// No description provided for @exportFormatHeif.
  ///
  /// In zh, this message translates to:
  /// **'HEIF'**
  String get exportFormatHeif;

  /// No description provided for @exportSize.
  ///
  /// In zh, this message translates to:
  /// **'输出尺寸'**
  String get exportSize;

  /// No description provided for @exportSizeOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原像素尺寸'**
  String get exportSizeOriginal;

  /// No description provided for @exportQuality.
  ///
  /// In zh, this message translates to:
  /// **'画质'**
  String get exportQuality;

  /// No description provided for @exportQualityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高画质'**
  String get exportQualityHigh;

  /// No description provided for @exportQualityStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get exportQualityStandard;

  /// No description provided for @exportQualityCompact.
  ///
  /// In zh, this message translates to:
  /// **'节省空间'**
  String get exportQualityCompact;

  /// No description provided for @exportColorSpaceNotice.
  ///
  /// In zh, this message translates to:
  /// **'首版统一以 sRGB 输出；原图不会被覆盖。'**
  String get exportColorSpaceNotice;

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

  /// No description provided for @flipHorizontal.
  ///
  /// In zh, this message translates to:
  /// **'水平翻转'**
  String get flipHorizontal;

  /// No description provided for @flipVertical.
  ///
  /// In zh, this message translates to:
  /// **'垂直翻转'**
  String get flipVertical;

  /// No description provided for @perspectiveHorizontal.
  ///
  /// In zh, this message translates to:
  /// **'水平透视'**
  String get perspectiveHorizontal;

  /// No description provided for @perspectiveVertical.
  ///
  /// In zh, this message translates to:
  /// **'垂直透视'**
  String get perspectiveVertical;

  /// No description provided for @filterAndHsl.
  ///
  /// In zh, this message translates to:
  /// **'滤镜与 HSL'**
  String get filterAndHsl;

  /// No description provided for @filterStrength.
  ///
  /// In zh, this message translates to:
  /// **'滤镜强度'**
  String get filterStrength;

  /// No description provided for @hslHue.
  ///
  /// In zh, this message translates to:
  /// **'色相'**
  String get hslHue;

  /// No description provided for @hslSaturation.
  ///
  /// In zh, this message translates to:
  /// **'饱和度'**
  String get hslSaturation;

  /// No description provided for @hslLightness.
  ///
  /// In zh, this message translates to:
  /// **'明度'**
  String get hslLightness;

  /// No description provided for @hslRed.
  ///
  /// In zh, this message translates to:
  /// **'红'**
  String get hslRed;

  /// No description provided for @hslOrange.
  ///
  /// In zh, this message translates to:
  /// **'橙'**
  String get hslOrange;

  /// No description provided for @hslYellow.
  ///
  /// In zh, this message translates to:
  /// **'黄'**
  String get hslYellow;

  /// No description provided for @hslGreen.
  ///
  /// In zh, this message translates to:
  /// **'绿'**
  String get hslGreen;

  /// No description provided for @hslCyan.
  ///
  /// In zh, this message translates to:
  /// **'青'**
  String get hslCyan;

  /// No description provided for @hslBlue.
  ///
  /// In zh, this message translates to:
  /// **'蓝'**
  String get hslBlue;

  /// No description provided for @hslPurple.
  ///
  /// In zh, this message translates to:
  /// **'紫'**
  String get hslPurple;

  /// No description provided for @hslMagenta.
  ///
  /// In zh, this message translates to:
  /// **'洋红'**
  String get hslMagenta;

  /// No description provided for @filterNone.
  ///
  /// In zh, this message translates to:
  /// **'原图'**
  String get filterNone;

  /// No description provided for @filterClean.
  ///
  /// In zh, this message translates to:
  /// **'清透'**
  String get filterClean;

  /// No description provided for @filterPortrait.
  ///
  /// In zh, this message translates to:
  /// **'人像'**
  String get filterPortrait;

  /// No description provided for @filterCinematic.
  ///
  /// In zh, this message translates to:
  /// **'电影'**
  String get filterCinematic;

  /// No description provided for @filterFilm.
  ///
  /// In zh, this message translates to:
  /// **'胶片'**
  String get filterFilm;

  /// No description provided for @filterWarmSun.
  ///
  /// In zh, this message translates to:
  /// **'暖阳'**
  String get filterWarmSun;

  /// No description provided for @filterCoolAir.
  ///
  /// In zh, this message translates to:
  /// **'冷空气'**
  String get filterCoolAir;

  /// No description provided for @filterVivid.
  ///
  /// In zh, this message translates to:
  /// **'鲜明'**
  String get filterVivid;

  /// No description provided for @filterFaded.
  ///
  /// In zh, this message translates to:
  /// **'褪色'**
  String get filterFaded;

  /// No description provided for @filterNoir.
  ///
  /// In zh, this message translates to:
  /// **'黑白'**
  String get filterNoir;

  /// No description provided for @filterFood.
  ///
  /// In zh, this message translates to:
  /// **'美食'**
  String get filterFood;

  /// No description provided for @filterLandscape.
  ///
  /// In zh, this message translates to:
  /// **'风景'**
  String get filterLandscape;

  /// No description provided for @filterNight.
  ///
  /// In zh, this message translates to:
  /// **'夜景'**
  String get filterNight;

  /// No description provided for @voiceEditEntry.
  ///
  /// In zh, this message translates to:
  /// **'说说怎么修'**
  String get voiceEditEntry;

  /// No description provided for @voiceEditPrompt.
  ///
  /// In zh, this message translates to:
  /// **'还想怎么改？'**
  String get voiceEditPrompt;

  /// No description provided for @quickEditBrighter.
  ///
  /// In zh, this message translates to:
  /// **'更亮一点'**
  String get quickEditBrighter;

  /// No description provided for @quickEditNaturalSkin.
  ///
  /// In zh, this message translates to:
  /// **'肤色自然一点'**
  String get quickEditNaturalSkin;

  /// No description provided for @manualAdjustments.
  ///
  /// In zh, this message translates to:
  /// **'手动调整'**
  String get manualAdjustments;

  /// No description provided for @manualAdjustmentsHint.
  ///
  /// In zh, this message translates to:
  /// **'需要时再展开全部参数'**
  String get manualAdjustmentsHint;

  /// No description provided for @savePhotos.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get savePhotos;

  /// No description provided for @voiceEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'描述你想要的效果'**
  String get voiceEditTitle;

  /// No description provided for @voiceEditHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：照片亮一点，皮肤自然一点'**
  String get voiceEditHint;

  /// No description provided for @voiceEditPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'语音只用于转写指令；修图结果仍由可见参数在本地生成。'**
  String get voiceEditPrivacy;

  /// No description provided for @voiceEditRecord.
  ///
  /// In zh, this message translates to:
  /// **'开始说话'**
  String get voiceEditRecord;

  /// No description provided for @voiceEditStop.
  ///
  /// In zh, this message translates to:
  /// **'完成录音'**
  String get voiceEditStop;

  /// No description provided for @voiceEditListening.
  ///
  /// In zh, this message translates to:
  /// **'正在听…'**
  String get voiceEditListening;

  /// No description provided for @voiceEditApply.
  ///
  /// In zh, this message translates to:
  /// **'应用修改'**
  String get voiceEditApply;

  /// No description provided for @voiceEditUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法安全理解这条指令，请换一种说法或手动调整。'**
  String get voiceEditUnsupported;

  /// No description provided for @voiceEditFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法使用语音，可以直接输入文字。'**
  String get voiceEditFailed;

  /// No description provided for @voiceEditApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用 {count} 项可见参数'**
  String voiceEditApplied(int count);
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
