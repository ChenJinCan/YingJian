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
  /// **'一张照片，专注修好'**
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

  /// No description provided for @homeSupporting.
  ///
  /// In zh, this message translates to:
  /// **'选张照片，说说想怎么改'**
  String get homeSupporting;

  /// No description provided for @homePrimaryAction.
  ///
  /// In zh, this message translates to:
  /// **'选择照片开始'**
  String get homePrimaryAction;

  /// No description provided for @homeChooseResult.
  ///
  /// In zh, this message translates to:
  /// **'选择想得到的结果'**
  String get homeChooseResult;

  /// No description provided for @imageApplication.
  ///
  /// In zh, this message translates to:
  /// **'图片应用'**
  String get imageApplication;

  /// No description provided for @imageApplicationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'换一种完整风格'**
  String get imageApplicationSubtitle;

  /// No description provided for @motionCreation.
  ///
  /// In zh, this message translates to:
  /// **'动起来'**
  String get motionCreation;

  /// No description provided for @motionCreationSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生成自然动态作品'**
  String get motionCreationSubtitle;

  /// No description provided for @optimizePhoto.
  ///
  /// In zh, this message translates to:
  /// **'优化照片'**
  String get optimizePhoto;

  /// No description provided for @optimizePhotoSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'调亮、清晰、增强质感'**
  String get optimizePhotoSubtitle;

  /// No description provided for @homeChangeStyle.
  ///
  /// In zh, this message translates to:
  /// **'换风格'**
  String get homeChangeStyle;

  /// No description provided for @changeStyleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'日系、胶片、插画、电影感'**
  String get changeStyleSubtitle;

  /// No description provided for @removeBackgroundOrObjects.
  ///
  /// In zh, this message translates to:
  /// **'去背景 / 去杂物'**
  String get removeBackgroundOrObjects;

  /// No description provided for @removeBackgroundOrObjectsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'抠图、白底、清理路人杂物'**
  String get removeBackgroundOrObjectsSubtitle;

  /// No description provided for @createMotionEffect.
  ///
  /// In zh, this message translates to:
  /// **'做动态效果'**
  String get createMotionEffect;

  /// No description provided for @createMotionEffectSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'让静态照片自然动起来'**
  String get createMotionEffectSubtitle;

  /// No description provided for @preparingImage.
  ///
  /// In zh, this message translates to:
  /// **'正在准备图片…'**
  String get preparingImage;

  /// No description provided for @recentCreations.
  ///
  /// In zh, this message translates to:
  /// **'最近创作'**
  String get recentCreations;

  /// No description provided for @continueCreation.
  ///
  /// In zh, this message translates to:
  /// **'继续创作'**
  String get continueCreation;

  /// No description provided for @currentStyle.
  ///
  /// In zh, this message translates to:
  /// **'当前风格'**
  String get currentStyle;

  /// No description provided for @currentResult.
  ///
  /// In zh, this message translates to:
  /// **'当前结果'**
  String get currentResult;

  /// No description provided for @capabilityUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'该能力尚未完成'**
  String get capabilityUnavailable;

  /// No description provided for @capabilityUnavailableDetail.
  ///
  /// In zh, this message translates to:
  /// **'当前不会处理、上传、创建任务或扣费。你可以返回能力列表自己选择下一步。'**
  String get capabilityUnavailableDetail;

  /// No description provided for @cloudCapabilitiesNotLoaded.
  ///
  /// In zh, this message translates to:
  /// **'云端能力待连接'**
  String get cloudCapabilitiesNotLoaded;

  /// No description provided for @cloudCapabilitiesNotLoadedDetail.
  ///
  /// In zh, this message translates to:
  /// **'尚未检查当前云端可用状态。点击重试只会连接并查询，不会上传、创建任务或扣费。'**
  String get cloudCapabilitiesNotLoadedDetail;

  /// No description provided for @cloudCapabilitiesLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在连接云端能力'**
  String get cloudCapabilitiesLoading;

  /// No description provided for @cloudCapabilitiesLoadingDetail.
  ///
  /// In zh, this message translates to:
  /// **'正在查询当前能力状态，不会上传照片、创建任务或扣费。'**
  String get cloudCapabilitiesLoadingDetail;

  /// No description provided for @cloudCapabilitiesConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'云端连接失败'**
  String get cloudCapabilitiesConnectionFailed;

  /// No description provided for @cloudCapabilitiesConnectionFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法确认当前能力状态。请检查网络后重试；不会自动上传、创建任务或扣费。'**
  String get cloudCapabilitiesConnectionFailedDetail;

  /// No description provided for @cloudCapabilityUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'该云端能力当前未开通'**
  String get cloudCapabilityUnavailable;

  /// No description provided for @cloudCapabilityUnavailableDetail.
  ///
  /// In zh, this message translates to:
  /// **'服务端当前没有为这项能力提供可执行额度。不会上传、创建任务或扣费。'**
  String get cloudCapabilityUnavailableDetail;

  /// No description provided for @cloudReconciliationRequired.
  ///
  /// In zh, this message translates to:
  /// **'云端任务状态待确认'**
  String get cloudReconciliationRequired;

  /// No description provided for @cloudReconciliationRequiredDetail.
  ///
  /// In zh, this message translates to:
  /// **'上一次请求可能已被云端接收。已暂停新建云端任务并保留当前权益状态；只会查询原请求，不会重复生成或重复扣费。'**
  String get cloudReconciliationRequiredDetail;

  /// No description provided for @checkCloudGenerationStatus.
  ///
  /// In zh, this message translates to:
  /// **'查询原任务状态'**
  String get checkCloudGenerationStatus;

  /// No description provided for @capabilityOptimizeNatural.
  ///
  /// In zh, this message translates to:
  /// **'自然优化'**
  String get capabilityOptimizeNatural;

  /// No description provided for @capabilityOptimizeAiRepair.
  ///
  /// In zh, this message translates to:
  /// **'AI 修复'**
  String get capabilityOptimizeAiRepair;

  /// No description provided for @capabilityOptimizeUpscale.
  ///
  /// In zh, this message translates to:
  /// **'高清放大'**
  String get capabilityOptimizeUpscale;

  /// No description provided for @capabilityOptimizeOldPhoto.
  ///
  /// In zh, this message translates to:
  /// **'老照片修复'**
  String get capabilityOptimizeOldPhoto;

  /// No description provided for @capabilityCleanupWhite.
  ///
  /// In zh, this message translates to:
  /// **'人物白底'**
  String get capabilityCleanupWhite;

  /// No description provided for @capabilityCleanupTransparent.
  ///
  /// In zh, this message translates to:
  /// **'透明抠图'**
  String get capabilityCleanupTransparent;

  /// No description provided for @capabilityCleanupReplaceBackground.
  ///
  /// In zh, this message translates to:
  /// **'替换背景'**
  String get capabilityCleanupReplaceBackground;

  /// No description provided for @capabilityCleanupRemovePasserby.
  ///
  /// In zh, this message translates to:
  /// **'去路人'**
  String get capabilityCleanupRemovePasserby;

  /// No description provided for @capabilityCleanupBrushRemove.
  ///
  /// In zh, this message translates to:
  /// **'涂抹去物'**
  String get capabilityCleanupBrushRemove;

  /// No description provided for @capabilityMotionSubtle.
  ///
  /// In zh, this message translates to:
  /// **'轻微动态'**
  String get capabilityMotionSubtle;

  /// No description provided for @capabilityMotionCameraPush.
  ///
  /// In zh, this message translates to:
  /// **'镜头推进'**
  String get capabilityMotionCameraPush;

  /// No description provided for @capabilityMotionLightFlow.
  ///
  /// In zh, this message translates to:
  /// **'光影流动'**
  String get capabilityMotionLightFlow;

  /// No description provided for @capabilityMotionAiNatural.
  ///
  /// In zh, this message translates to:
  /// **'AI 自然动效'**
  String get capabilityMotionAiNatural;

  /// No description provided for @generatingResult.
  ///
  /// In zh, this message translates to:
  /// **'正在生成…'**
  String get generatingResult;

  /// No description provided for @upscaleReady.
  ///
  /// In zh, this message translates to:
  /// **'高清图片已生成，可分享或保存。'**
  String get upscaleReady;

  /// No description provided for @motionReady.
  ///
  /// In zh, this message translates to:
  /// **'动态照片已生成，可分享或保存。'**
  String get motionReady;

  /// No description provided for @generationFailed.
  ///
  /// In zh, this message translates to:
  /// **'生成失败，请重试。'**
  String get generationFailed;

  /// No description provided for @generationConcurrencyExceeded.
  ///
  /// In zh, this message translates to:
  /// **'已有云端任务仍在处理或待确认，暂时不能创建新的云端任务。'**
  String get generationConcurrencyExceeded;

  /// No description provided for @generationCreditExhausted.
  ///
  /// In zh, this message translates to:
  /// **'当前云端权益不足，任务没有开始。'**
  String get generationCreditExhausted;

  /// No description provided for @generationCapabilityDisabled.
  ///
  /// In zh, this message translates to:
  /// **'该云端能力当前未开通，任务没有开始。'**
  String get generationCapabilityDisabled;

  /// No description provided for @generationProviderFailed.
  ///
  /// In zh, this message translates to:
  /// **'云端供应商处理失败，请保留当前结果后再决定是否重试。'**
  String get generationProviderFailed;

  /// No description provided for @cloudGenerationConsentTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认云端处理'**
  String get cloudGenerationConsentTitle;

  /// No description provided for @cloudGenerationConsentDetail.
  ///
  /// In zh, this message translates to:
  /// **'确认后才会上传并创建这一项任务；处理可能需要等待，可取消阶段会显示取消操作。源图、蒙版和云端结果在网关最多保留 24 小时。'**
  String get cloudGenerationConsentDetail;

  /// No description provided for @cloudUploadConsent.
  ///
  /// In zh, this message translates to:
  /// **'同意上传当前照片完成所选能力'**
  String get cloudUploadConsent;

  /// No description provided for @cloudCostConsent.
  ///
  /// In zh, this message translates to:
  /// **'确认消耗 {creditCost} 次云端权益'**
  String cloudCostConsent(int creditCost);

  /// No description provided for @confirmAndGenerate.
  ///
  /// In zh, this message translates to:
  /// **'确认并生成'**
  String get confirmAndGenerate;

  /// No description provided for @confirmCloudGeneration.
  ///
  /// In zh, this message translates to:
  /// **'开始云端处理'**
  String get confirmCloudGeneration;

  /// No description provided for @cloudGenerationReady.
  ///
  /// In zh, this message translates to:
  /// **'云端处理结果已生成，可分享或保存。'**
  String get cloudGenerationReady;

  /// No description provided for @cloudGenerationQueued.
  ///
  /// In zh, this message translates to:
  /// **'任务已创建，正在等待云端处理。'**
  String get cloudGenerationQueued;

  /// No description provided for @cloudGenerationRunning.
  ///
  /// In zh, this message translates to:
  /// **'云端正在处理所选能力。'**
  String get cloudGenerationRunning;

  /// No description provided for @cancelGeneration.
  ///
  /// In zh, this message translates to:
  /// **'取消这次处理'**
  String get cancelGeneration;

  /// No description provided for @generationCancelled.
  ///
  /// In zh, this message translates to:
  /// **'这次处理已取消，原图和已有结果没有改变。'**
  String get generationCancelled;

  /// No description provided for @generationCancelledCreditReleased.
  ///
  /// In zh, this message translates to:
  /// **'这次处理已取消，本次权益已释放；原图和已有结果没有改变。'**
  String get generationCancelledCreditReleased;

  /// No description provided for @generationCancellationStillRunning.
  ///
  /// In zh, this message translates to:
  /// **'供应商已经开始处理，无法取消；同一任务继续运行，权益仍暂时占用。'**
  String get generationCancellationStillRunning;

  /// No description provided for @generationStatusCreditHeld.
  ///
  /// In zh, this message translates to:
  /// **'处理结果仍需确认，权益暂时保留。请刷新同一任务，不会新建任务或再次扣费。'**
  String get generationStatusCreditHeld;

  /// No description provided for @previewMotionResult.
  ///
  /// In zh, this message translates to:
  /// **'播放动态结果'**
  String get previewMotionResult;

  /// No description provided for @chooseOldPhotoColorMode.
  ///
  /// In zh, this message translates to:
  /// **'选择老照片的颜色处理'**
  String get chooseOldPhotoColorMode;

  /// No description provided for @oldPhotoPreserveColor.
  ///
  /// In zh, this message translates to:
  /// **'保留原有色彩'**
  String get oldPhotoPreserveColor;

  /// No description provided for @oldPhotoColorize.
  ///
  /// In zh, this message translates to:
  /// **'智能上色'**
  String get oldPhotoColorize;

  /// No description provided for @aiRedrawDefinitionSummary.
  ///
  /// In zh, this message translates to:
  /// **'只按你确认的生成意图重绘，不会自动改成其他方向。'**
  String get aiRedrawDefinitionSummary;

  /// No description provided for @markRemovalArea.
  ///
  /// In zh, this message translates to:
  /// **'涂抹要移除的区域'**
  String get markRemovalArea;

  /// No description provided for @changeRemovalArea.
  ///
  /// In zh, this message translates to:
  /// **'重新涂抹区域'**
  String get changeRemovalArea;

  /// No description provided for @removalAreaReady.
  ///
  /// In zh, this message translates to:
  /// **'已使用你手动涂抹的区域，不会自动选择其他内容。'**
  String get removalAreaReady;

  /// No description provided for @applyWhiteBackground.
  ///
  /// In zh, this message translates to:
  /// **'应用白底'**
  String get applyWhiteBackground;

  /// No description provided for @applyTransparentBackground.
  ///
  /// In zh, this message translates to:
  /// **'生成透明抠图'**
  String get applyTransparentBackground;

  /// No description provided for @applyReplacementBackground.
  ///
  /// In zh, this message translates to:
  /// **'应用新背景'**
  String get applyReplacementBackground;

  /// No description provided for @chooseReplacementBackground.
  ///
  /// In zh, this message translates to:
  /// **'选择新背景'**
  String get chooseReplacementBackground;

  /// No description provided for @chooseAnotherBackground.
  ///
  /// In zh, this message translates to:
  /// **'更换背景图片'**
  String get chooseAnotherBackground;

  /// No description provided for @importingBackground.
  ///
  /// In zh, this message translates to:
  /// **'正在导入背景…'**
  String get importingBackground;

  /// No description provided for @optimizeResult.
  ///
  /// In zh, this message translates to:
  /// **'自动优化'**
  String get optimizeResult;

  /// No description provided for @cleanupResult.
  ///
  /// In zh, this message translates to:
  /// **'白底清理'**
  String get cleanupResult;

  /// No description provided for @optimizeApplied.
  ///
  /// In zh, this message translates to:
  /// **'照片已优化'**
  String get optimizeApplied;

  /// No description provided for @cleanupApplied.
  ///
  /// In zh, this message translates to:
  /// **'清理已应用'**
  String get cleanupApplied;

  /// No description provided for @optimizeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新优化'**
  String get optimizeAgain;

  /// No description provided for @cleanupAgain.
  ///
  /// In zh, this message translates to:
  /// **'继续清理'**
  String get cleanupAgain;

  /// No description provided for @cleanupWhiteBackgroundUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可安全处理的主体，本次人物白底不会执行。'**
  String get cleanupWhiteBackgroundUnavailable;

  /// No description provided for @cleanupSubjectUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可安全处理的主体，本次背景处理不会执行。'**
  String get cleanupSubjectUnavailable;

  /// No description provided for @localStaticTaskIosOnly.
  ///
  /// In zh, this message translates to:
  /// **'该本地处理当前仅支持 iPhone。'**
  String get localStaticTaskIosOnly;

  /// No description provided for @aiDefineStyle.
  ///
  /// In zh, this message translates to:
  /// **'AI 定风格'**
  String get aiDefineStyle;

  /// No description provided for @describeStyleTitle.
  ///
  /// In zh, this message translates to:
  /// **'描述你的风格'**
  String get describeStyleTitle;

  /// No description provided for @describeStyleHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：雨后的电影感，人物保持自然'**
  String get describeStyleHint;

  /// No description provided for @styleDefinitionInputHint.
  ///
  /// In zh, this message translates to:
  /// **'可用文字、确认后的语音转写或单独的参考图定义风格；源照片始终是结果主体。'**
  String get styleDefinitionInputHint;

  /// No description provided for @styleInputText.
  ///
  /// In zh, this message translates to:
  /// **'文字'**
  String get styleInputText;

  /// No description provided for @styleInputVoice.
  ///
  /// In zh, this message translates to:
  /// **'语音'**
  String get styleInputVoice;

  /// No description provided for @styleInputReference.
  ///
  /// In zh, this message translates to:
  /// **'参考图'**
  String get styleInputReference;

  /// No description provided for @styleVoiceTranscriptHint.
  ///
  /// In zh, this message translates to:
  /// **'先说出你的想法，再确认或修改转写内容后定义风格。'**
  String get styleVoiceTranscriptHint;

  /// No description provided for @styleVoiceRecord.
  ///
  /// In zh, this message translates to:
  /// **'开始录音'**
  String get styleVoiceRecord;

  /// No description provided for @styleVoiceStop.
  ///
  /// In zh, this message translates to:
  /// **'停止录音'**
  String get styleVoiceStop;

  /// No description provided for @styleVoiceListening.
  ///
  /// In zh, this message translates to:
  /// **'正在聆听…'**
  String get styleVoiceListening;

  /// No description provided for @styleVoiceFailed.
  ///
  /// In zh, this message translates to:
  /// **'语音暂未转写成功。当前图片和输入均已保留。'**
  String get styleVoiceFailed;

  /// No description provided for @styleReferenceHint.
  ///
  /// In zh, this message translates to:
  /// **'单独选择一张参考图。只提取色彩、光线、质感和氛围，不复制人物、物体、文字或构图。'**
  String get styleReferenceHint;

  /// No description provided for @styleReferenceChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择参考图'**
  String get styleReferenceChoose;

  /// No description provided for @styleReferenceSource.
  ///
  /// In zh, this message translates to:
  /// **'源照片'**
  String get styleReferenceSource;

  /// No description provided for @styleReferenceImage.
  ///
  /// In zh, this message translates to:
  /// **'风格参考'**
  String get styleReferenceImage;

  /// No description provided for @styleReferenceRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除参考图'**
  String get styleReferenceRemove;

  /// No description provided for @styleReferenceKeptLocal.
  ///
  /// In zh, this message translates to:
  /// **'参考图不会替换源照片；风格定义完成后会移除本地临时副本。'**
  String get styleReferenceKeptLocal;

  /// No description provided for @styleReferenceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备无法使用参考图。当前图片保持不变。'**
  String get styleReferenceUnavailable;

  /// No description provided for @styleReferenceFailed.
  ///
  /// In zh, this message translates to:
  /// **'这张参考图暂时无法使用，源照片和当前风格均未改变。'**
  String get styleReferenceFailed;

  /// No description provided for @defineStyle.
  ///
  /// In zh, this message translates to:
  /// **'定义风格'**
  String get defineStyle;

  /// No description provided for @styleNotUnderstood.
  ///
  /// In zh, this message translates to:
  /// **'暂时没理解。试试“电影感”“暖一点”或“清冷一点”。'**
  String get styleNotUnderstood;

  /// No description provided for @styleAiCustom.
  ///
  /// In zh, this message translates to:
  /// **'AI 风格'**
  String get styleAiCustom;

  /// No description provided for @styleSavedCustom.
  ///
  /// In zh, this message translates to:
  /// **'已保存风格'**
  String get styleSavedCustom;

  /// No description provided for @styleOfficialDefinitionSummary.
  ///
  /// In zh, this message translates to:
  /// **'固定且可复现的本地风格。'**
  String get styleOfficialDefinitionSummary;

  /// No description provided for @styleTextDefinitionSummary.
  ///
  /// In zh, this message translates to:
  /// **'根据你确认的文字描述生成的本地风格。'**
  String get styleTextDefinitionSummary;

  /// No description provided for @styleVoiceDefinitionSummary.
  ///
  /// In zh, this message translates to:
  /// **'根据你确认的语音转写生成的本地风格。'**
  String get styleVoiceDefinitionSummary;

  /// No description provided for @styleReferenceDefinitionSummary.
  ///
  /// In zh, this message translates to:
  /// **'只使用参考图的色彩、光线、质感与氛围生成的本地风格。'**
  String get styleReferenceDefinitionSummary;

  /// No description provided for @styleReferenceWarmTitle.
  ///
  /// In zh, this message translates to:
  /// **'暖调参考'**
  String get styleReferenceWarmTitle;

  /// No description provided for @styleReferenceCoolTitle.
  ///
  /// In zh, this message translates to:
  /// **'冷调参考'**
  String get styleReferenceCoolTitle;

  /// No description provided for @styleReferenceNaturalTitle.
  ///
  /// In zh, this message translates to:
  /// **'自然参考'**
  String get styleReferenceNaturalTitle;

  /// No description provided for @styleJapanese.
  ///
  /// In zh, this message translates to:
  /// **'日系'**
  String get styleJapanese;

  /// No description provided for @styleFilm.
  ///
  /// In zh, this message translates to:
  /// **'胶片'**
  String get styleFilm;

  /// No description provided for @styleIllustration.
  ///
  /// In zh, this message translates to:
  /// **'插画'**
  String get styleIllustration;

  /// No description provided for @styleCinematic.
  ///
  /// In zh, this message translates to:
  /// **'电影感'**
  String get styleCinematic;

  /// No description provided for @styleIllustrationIntent.
  ///
  /// In zh, this message translates to:
  /// **'保留人物身份、五官、姿势和原始构图，转换为精致自然的手绘插画风格；线条干净，色彩柔和，细节完整，不添加文字、水印或无关物体。'**
  String get styleIllustrationIntent;

  /// No description provided for @styleNatural.
  ///
  /// In zh, this message translates to:
  /// **'自然'**
  String get styleNatural;

  /// No description provided for @styleSoftLight.
  ///
  /// In zh, this message translates to:
  /// **'柔光'**
  String get styleSoftLight;

  /// No description provided for @styleNight.
  ///
  /// In zh, this message translates to:
  /// **'夜色'**
  String get styleNight;

  /// No description provided for @styleCool.
  ///
  /// In zh, this message translates to:
  /// **'清冷'**
  String get styleCool;

  /// No description provided for @styleWarmSun.
  ///
  /// In zh, this message translates to:
  /// **'暖阳'**
  String get styleWarmSun;

  /// No description provided for @styleMono.
  ///
  /// In zh, this message translates to:
  /// **'黑白'**
  String get styleMono;

  /// No description provided for @styleBreeze.
  ///
  /// In zh, this message translates to:
  /// **'微风'**
  String get styleBreeze;

  /// No description provided for @styleBreathe.
  ///
  /// In zh, this message translates to:
  /// **'呼吸'**
  String get styleBreathe;

  /// No description provided for @stylePushIn.
  ///
  /// In zh, this message translates to:
  /// **'推进'**
  String get stylePushIn;

  /// No description provided for @styleFlowingLight.
  ///
  /// In zh, this message translates to:
  /// **'流光'**
  String get styleFlowingLight;

  /// No description provided for @styleCinema.
  ///
  /// In zh, this message translates to:
  /// **'电影'**
  String get styleCinema;

  /// No description provided for @applyStyle.
  ///
  /// In zh, this message translates to:
  /// **'应用风格'**
  String get applyStyle;

  /// No description provided for @applyingStyle.
  ///
  /// In zh, this message translates to:
  /// **'正在应用…'**
  String get applyingStyle;

  /// No description provided for @styleApplied.
  ///
  /// In zh, this message translates to:
  /// **'风格已应用'**
  String get styleApplied;

  /// No description provided for @changeStyle.
  ///
  /// In zh, this message translates to:
  /// **'换个风格'**
  String get changeStyle;

  /// No description provided for @generateMotion.
  ///
  /// In zh, this message translates to:
  /// **'生成动态照片'**
  String get generateMotion;

  /// No description provided for @motionConfirmationTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成动态作品'**
  String get motionConfirmationTitle;

  /// No description provided for @motionConfirmationBody.
  ///
  /// In zh, this message translates to:
  /// **'确认后才会上传这张图片并创建动态任务。当前工程切片尚未接入生成服务，不会上传或消耗权益。'**
  String get motionConfirmationBody;

  /// No description provided for @motionUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'动态生成服务尚未接入'**
  String get motionUnavailable;

  /// No description provided for @motionUnavailableDetail.
  ///
  /// In zh, this message translates to:
  /// **'当前不会上传图片、创建任务或消耗额度。你可以返回能力列表或首页。'**
  String get motionUnavailableDetail;

  /// No description provided for @gotIt.
  ///
  /// In zh, this message translates to:
  /// **'知道了'**
  String get gotIt;

  /// No description provided for @onboardingPromise.
  ///
  /// In zh, this message translates to:
  /// **'选一张照片，再说出你想要的感觉。映见专注把这一张修好。'**
  String get onboardingPromise;

  /// No description provided for @onboardingContinue.
  ///
  /// In zh, this message translates to:
  /// **'开始使用'**
  String get onboardingContinue;

  /// No description provided for @onboardingSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法保存首次使用状态，请重试。'**
  String get onboardingSaveFailed;

  /// No description provided for @recentProjects.
  ///
  /// In zh, this message translates to:
  /// **'最近项目'**
  String get recentProjects;

  /// No description provided for @otherDrafts.
  ///
  /// In zh, this message translates to:
  /// **'其他草稿'**
  String get otherDrafts;

  /// No description provided for @selectNewPhoto.
  ///
  /// In zh, this message translates to:
  /// **'选择新照片'**
  String get selectNewPhoto;

  /// No description provided for @deleteDraft.
  ///
  /// In zh, this message translates to:
  /// **'删除草稿'**
  String get deleteDraft;

  /// No description provided for @draftDeleteConfirmation.
  ///
  /// In zh, this message translates to:
  /// **'会删除映见中的草稿、生成结果，并取消仍可取消的云端任务；不会删除系统相册原图。云端任务已无法取消时，本次不会删除。'**
  String get draftDeleteConfirmation;

  /// No description provided for @draftStatusEditing.
  ///
  /// In zh, this message translates to:
  /// **'编辑中'**
  String get draftStatusEditing;

  /// No description provided for @draftStatusExported.
  ///
  /// In zh, this message translates to:
  /// **'已导出'**
  String get draftStatusExported;

  /// No description provided for @draftStatusModified.
  ///
  /// In zh, this message translates to:
  /// **'有新修改'**
  String get draftStatusModified;

  /// No description provided for @draftStatusNeedsUpdate.
  ///
  /// In zh, this message translates to:
  /// **'需要更新'**
  String get draftStatusNeedsUpdate;

  /// No description provided for @draftStatusNeedsRecovery.
  ///
  /// In zh, this message translates to:
  /// **'需要恢复'**
  String get draftStatusNeedsRecovery;

  /// No description provided for @lastEditedAt.
  ///
  /// In zh, this message translates to:
  /// **'最后编辑于 {date} {time}'**
  String lastEditedAt(String date, String time);

  /// No description provided for @noRecentProjects.
  ///
  /// In zh, this message translates to:
  /// **'还没有项目，选一张照片开始吧'**
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

  /// No description provided for @projectDeleteCloudTaskActive.
  ///
  /// In zh, this message translates to:
  /// **'云端任务已经开始且暂时无法取消；为保留任务与权益状态，本次没有删除创作。'**
  String get projectDeleteCloudTaskActive;

  /// No description provided for @projectDeletedGenerationCleanupPending.
  ///
  /// In zh, this message translates to:
  /// **'创作已删除，但本地生成缓存尚未清理完成。系统相册内容不受影响。'**
  String get projectDeletedGenerationCleanupPending;

  /// No description provided for @lastProjectSummary.
  ///
  /// In zh, this message translates to:
  /// **'1 张照片 · 最后编辑于 {date} {time}'**
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

  /// No description provided for @preparingStylePreview.
  ///
  /// In zh, this message translates to:
  /// **'正在准备风格预览'**
  String get preparingStylePreview;

  /// No description provided for @stylePreviewReady.
  ///
  /// In zh, this message translates to:
  /// **'风格预览已就绪'**
  String get stylePreviewReady;

  /// No description provided for @stylePreviewFailedShowingOriginal.
  ///
  /// In zh, this message translates to:
  /// **'风格预览失败，已保留当前画面'**
  String get stylePreviewFailedShowingOriginal;

  /// No description provided for @restorePreviousResult.
  ///
  /// In zh, this message translates to:
  /// **'返回上次成片'**
  String get restorePreviousResult;

  /// No description provided for @selectPhotosTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择一张照片'**
  String get selectPhotosTitle;

  /// No description provided for @selectPhotos.
  ///
  /// In zh, this message translates to:
  /// **'选择照片'**
  String get selectPhotos;

  /// No description provided for @photoLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取这张照片'**
  String get photoLoadFailed;

  /// No description provided for @compositionPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'构图预览暂不可用，可恢复原始构图或稍后重试。'**
  String get compositionPreviewUnavailable;

  /// No description provided for @effectPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前效果预览暂不可用，请重试。'**
  String get effectPreviewUnavailable;

  /// No description provided for @photoImportCanceled.
  ///
  /// In zh, this message translates to:
  /// **'未添加任何照片'**
  String get photoImportCanceled;

  /// No description provided for @importingPhotos.
  ///
  /// In zh, this message translates to:
  /// **'正在导入照片…'**
  String get importingPhotos;

  /// No description provided for @preparingPhoto.
  ///
  /// In zh, this message translates to:
  /// **'正在准备照片…'**
  String get preparingPhoto;

  /// No description provided for @restoringProject.
  ///
  /// In zh, this message translates to:
  /// **'正在恢复项目…'**
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
  /// **'当前项目已有一张照片'**
  String get photoLimitReached;

  /// No description provided for @projectRestoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法恢复上次项目'**
  String get projectRestoreFailed;

  /// No description provided for @taskRouteMismatch.
  ///
  /// In zh, this message translates to:
  /// **'这个草稿不属于当前任务，请返回首页继续。'**
  String get taskRouteMismatch;

  /// No description provided for @projectSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存本次调整，请重试'**
  String get projectSaveFailed;

  /// No description provided for @editSavePending.
  ///
  /// In zh, this message translates to:
  /// **'正在保存本次调整'**
  String get editSavePending;

  /// No description provided for @editSaveRecoveryMessage.
  ///
  /// In zh, this message translates to:
  /// **'本次调整尚未保存，当前仍显示上次安全结果。'**
  String get editSaveRecoveryMessage;

  /// No description provided for @discardAdjustment.
  ///
  /// In zh, this message translates to:
  /// **'放弃本次调整'**
  String get discardAdjustment;

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
  /// **'自然美化'**
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
  /// **'当前画面的背景线条与面部区域重叠，瘦脸暂不生效'**
  String get faceSlimBackgroundProtected;

  /// No description provided for @faceSlimMultipleFaces.
  ///
  /// In zh, this message translates to:
  /// **'检测到多个人脸，请选择要调整的人物'**
  String get faceSlimMultipleFaces;

  /// No description provided for @faceSlimUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可调整的面部，瘦脸不会生效'**
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

  /// No description provided for @bodyToolsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可调整的人物，身形调整不会生效'**
  String get bodyToolsUnavailable;

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
  /// **'背景'**
  String get semanticTools;

  /// No description provided for @mobileToolRetouch.
  ///
  /// In zh, this message translates to:
  /// **'人像'**
  String get mobileToolRetouch;

  /// No description provided for @semanticToolsLocalReady.
  ///
  /// In zh, this message translates to:
  /// **'可以调整背景'**
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
  /// **'光线'**
  String get lightAndColorTools;

  /// No description provided for @localPortraitReady.
  ///
  /// In zh, this message translates to:
  /// **'可以调整人像'**
  String get localPortraitReady;

  /// No description provided for @portraitToolsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可调整的人像，人像效果不会生效'**
  String get portraitToolsUnavailable;

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

  /// No description provided for @shareResult.
  ///
  /// In zh, this message translates to:
  /// **'分享成片'**
  String get shareResult;

  /// No description provided for @preparingShare.
  ///
  /// In zh, this message translates to:
  /// **'正在准备分享…'**
  String get preparingShare;

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
  /// **'已取消分享，成片仍已保存到系统相册'**
  String get photoShareCanceled;

  /// No description provided for @photoShareFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法分享，成片仍已保存到系统相册'**
  String get photoShareFailed;

  /// No description provided for @photoResultShareCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消分享'**
  String get photoResultShareCanceled;

  /// No description provided for @photoResultShareFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法分享，请重试'**
  String get photoResultShareFailed;

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
  /// **'颜色'**
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

  /// No description provided for @quickNatural.
  ///
  /// In zh, this message translates to:
  /// **'自然一点'**
  String get quickNatural;

  /// No description provided for @quickBrighten.
  ///
  /// In zh, this message translates to:
  /// **'亮一点'**
  String get quickBrighten;

  /// No description provided for @quickAtmosphere.
  ///
  /// In zh, this message translates to:
  /// **'换氛围'**
  String get quickAtmosphere;

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

  /// No description provided for @quickEditAtmosphere.
  ///
  /// In zh, this message translates to:
  /// **'整体更有氛围'**
  String get quickEditAtmosphere;

  /// No description provided for @quickEditSoftBackground.
  ///
  /// In zh, this message translates to:
  /// **'背景柔和一点'**
  String get quickEditSoftBackground;

  /// No description provided for @onlyEditThisPhoto.
  ///
  /// In zh, this message translates to:
  /// **'只改这张'**
  String get onlyEditThisPhoto;

  /// No description provided for @syncToAllPhotos.
  ///
  /// In zh, this message translates to:
  /// **'同步到全部'**
  String get syncToAllPhotos;

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

  /// No description provided for @adjustPhoto.
  ///
  /// In zh, this message translates to:
  /// **'自己调'**
  String get adjustPhoto;

  /// No description provided for @quickAdjust.
  ///
  /// In zh, this message translates to:
  /// **'快速调整'**
  String get quickAdjust;

  /// No description provided for @allTools.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get allTools;

  /// No description provided for @metaOpSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索调整能力'**
  String get metaOpSearchHint;

  /// No description provided for @metaOpSearchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到可用能力'**
  String get metaOpSearchNoResults;

  /// No description provided for @savePhotos.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get savePhotos;

  /// No description provided for @preparingExport.
  ///
  /// In zh, this message translates to:
  /// **'正在准备成片…'**
  String get preparingExport;

  /// No description provided for @canvasInteractionHint.
  ///
  /// In zh, this message translates to:
  /// **'点按全屏 · 长按看原图'**
  String get canvasInteractionHint;

  /// No description provided for @savingToSystemPhotos.
  ///
  /// In zh, this message translates to:
  /// **'正在保存到系统相册…'**
  String get savingToSystemPhotos;

  /// No description provided for @savedToSystemPhotos.
  ///
  /// In zh, this message translates to:
  /// **'已保存到系统相册'**
  String get savedToSystemPhotos;

  /// No description provided for @exportFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法导出'**
  String get exportFailedTitle;

  /// No description provided for @photoPermissionPurpose.
  ///
  /// In zh, this message translates to:
  /// **'映见需要添加照片权限，才能把成片保存到系统相册。'**
  String get photoPermissionPurpose;

  /// No description provided for @goToSystemSettings.
  ///
  /// In zh, this message translates to:
  /// **'前往系统设置'**
  String get goToSystemSettings;

  /// No description provided for @saveOptionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'完成优化'**
  String get saveOptionsTitle;

  /// No description provided for @saveOptionsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要保存的照片'**
  String get saveOptionsSubtitle;

  /// No description provided for @saveToAlbum.
  ///
  /// In zh, this message translates to:
  /// **'保存到相册'**
  String get saveToAlbum;

  /// No description provided for @savingProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在保存 {current}/{total}'**
  String savingProgress(int current, int total);

  /// No description provided for @photoNumber.
  ///
  /// In zh, this message translates to:
  /// **'第 {number} 张'**
  String photoNumber(int number);

  /// No description provided for @cancelRemainingPhotos.
  ///
  /// In zh, this message translates to:
  /// **'取消剩余照片'**
  String get cancelRemainingPhotos;

  /// No description provided for @savedPhotosAreKept.
  ///
  /// In zh, this message translates to:
  /// **'已经保存的照片会保留'**
  String get savedPhotosAreKept;

  /// No description provided for @partialSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {saved} 张，{failed} 张暂未保存'**
  String partialSaveTitle(int saved, int failed);

  /// No description provided for @photoLibraryTemporarilyUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'相册暂时无法写入'**
  String get photoLibraryTemporarilyUnavailable;

  /// No description provided for @retryPhotoCount.
  ///
  /// In zh, this message translates to:
  /// **'重试这 {count} 张'**
  String retryPhotoCount(int count);

  /// No description provided for @viewSavedPhotos.
  ///
  /// In zh, this message translates to:
  /// **'查看已保存'**
  String get viewSavedPhotos;

  /// No description provided for @backToEditing.
  ///
  /// In zh, this message translates to:
  /// **'回到编辑'**
  String get backToEditing;

  /// No description provided for @voiceEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'想怎么改？'**
  String get voiceEditTitle;

  /// No description provided for @voiceEditHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：照片亮一点，皮肤自然一点'**
  String get voiceEditHint;

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
  /// **'还没理解这条调整。可以换种说法，或直接手动调整。'**
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

  /// No description provided for @voiceEditDone.
  ///
  /// In zh, this message translates to:
  /// **'已经改好了'**
  String get voiceEditDone;

  /// No description provided for @editResultBrighter.
  ///
  /// In zh, this message translates to:
  /// **'已让这张更亮'**
  String get editResultBrighter;

  /// No description provided for @editResultApplied.
  ///
  /// In zh, this message translates to:
  /// **'已完成这次修改'**
  String get editResultApplied;

  /// No description provided for @editApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用'**
  String get editApplied;

  /// No description provided for @manualSimpleHint.
  ///
  /// In zh, this message translates to:
  /// **'选一个你想要的结果'**
  String get manualSimpleHint;

  /// No description provided for @manualBrighter.
  ///
  /// In zh, this message translates to:
  /// **'亮一点'**
  String get manualBrighter;

  /// No description provided for @manualWarmer.
  ///
  /// In zh, this message translates to:
  /// **'暖一点'**
  String get manualWarmer;

  /// No description provided for @manualMoreVivid.
  ///
  /// In zh, this message translates to:
  /// **'鲜艳一点'**
  String get manualMoreVivid;

  /// No description provided for @manualNaturalSkin.
  ///
  /// In zh, this message translates to:
  /// **'自然肤色'**
  String get manualNaturalSkin;

  /// No description provided for @manualSmootherSkin.
  ///
  /// In zh, this message translates to:
  /// **'皮肤更细腻'**
  String get manualSmootherSkin;

  /// No description provided for @manualSmallerFace.
  ///
  /// In zh, this message translates to:
  /// **'脸小一点'**
  String get manualSmallerFace;

  /// No description provided for @manualNaturalBody.
  ///
  /// In zh, this message translates to:
  /// **'身形更自然'**
  String get manualNaturalBody;

  /// No description provided for @choosePersonTitle.
  ///
  /// In zh, this message translates to:
  /// **'想修谁？'**
  String get choosePersonTitle;

  /// No description provided for @choosePersonHint.
  ///
  /// In zh, this message translates to:
  /// **'点一下照片里的人'**
  String get choosePersonHint;

  /// No description provided for @saveSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 张照片'**
  String saveSuccess(int count);

  /// No description provided for @finish.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get finish;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @fullscreenPreview.
  ///
  /// In zh, this message translates to:
  /// **'全屏查看'**
  String get fullscreenPreview;

  /// No description provided for @fullscreenAdjusted.
  ///
  /// In zh, this message translates to:
  /// **'调整后'**
  String get fullscreenAdjusted;

  /// No description provided for @fullscreenPreviewHint.
  ///
  /// In zh, this message translates to:
  /// **'轻点返回调整 · 按住看原图'**
  String get fullscreenPreviewHint;

  /// No description provided for @projectRequiresUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'需要更新后继续编辑'**
  String get projectRequiresUpdateTitle;

  /// No description provided for @projectRequiresUpdateMessage.
  ///
  /// In zh, this message translates to:
  /// **'这组照片包含当前版本尚不支持的效果。已完整保留，只能查看，更新应用后可继续编辑和保存。'**
  String get projectRequiresUpdateMessage;

  /// No description provided for @visualTracksTitle.
  ///
  /// In zh, this message translates to:
  /// **'视觉轨道'**
  String get visualTracksTitle;

  /// No description provided for @visualTracksEntry.
  ///
  /// In zh, this message translates to:
  /// **'视觉轨道'**
  String get visualTracksEntry;

  /// No description provided for @visualTracksNotApplied.
  ///
  /// In zh, this message translates to:
  /// **'没有应用这次变化'**
  String get visualTracksNotApplied;

  /// No description provided for @eraAtmosphereTrack.
  ///
  /// In zh, this message translates to:
  /// **'时代氛围'**
  String get eraAtmosphereTrack;

  /// No description provided for @lightingTrack.
  ///
  /// In zh, this message translates to:
  /// **'光照'**
  String get lightingTrack;

  /// No description provided for @vintageFilm.
  ///
  /// In zh, this message translates to:
  /// **'复古胶片'**
  String get vintageFilm;

  /// No description provided for @currentEffect.
  ///
  /// In zh, this message translates to:
  /// **'当前效果'**
  String get currentEffect;

  /// No description provided for @nearFuture.
  ///
  /// In zh, this message translates to:
  /// **'近未来'**
  String get nearFuture;

  /// No description provided for @lightingNeedsPerson.
  ///
  /// In zh, this message translates to:
  /// **'暂未识别到可调整光照的人物，其他光色工具仍可使用'**
  String get lightingNeedsPerson;

  /// No description provided for @personNumber.
  ///
  /// In zh, this message translates to:
  /// **'人物 {number}'**
  String personNumber(int number);

  /// No description provided for @leftLight.
  ///
  /// In zh, this message translates to:
  /// **'左侧光'**
  String get leftLight;

  /// No description provided for @frontLight.
  ///
  /// In zh, this message translates to:
  /// **'正面光'**
  String get frontLight;

  /// No description provided for @rightLight.
  ///
  /// In zh, this message translates to:
  /// **'右侧光'**
  String get rightLight;
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
