// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '映见';

  @override
  String get homeTagline => '一张精修，整组好看';

  @override
  String get startEditing => '开始修图';

  @override
  String get editorTitle => '精修工作台';

  @override
  String get undo => '撤销';

  @override
  String get reset => '重置';

  @override
  String get photoPreviewArea => '照片预览区域';

  @override
  String get exposure => '曝光';

  @override
  String get contrast => '对比度';

  @override
  String get warmth => '色温';

  @override
  String get unknownPageTitle => '页面不存在';

  @override
  String get unknownPageMessage => '暂时无法打开这个页面';
}
