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
  /// **'选择 1–9 张照片'**
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
  /// **'{count}/9'**
  String photoCount(int count);

  /// No description provided for @photoLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取这张照片'**
  String get photoLoadFailed;

  /// No description provided for @photoImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'照片导入失败，请重试'**
  String get photoImportFailed;

  /// No description provided for @photoLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'每个项目最多导入 9 张照片'**
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
