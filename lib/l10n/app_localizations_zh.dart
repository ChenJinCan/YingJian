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
  String get redo => '重做';

  @override
  String get reset => '重置';

  @override
  String get photoPreviewArea => '照片预览区域';

  @override
  String get selectPhotosTitle => '选择 1–6 张照片';

  @override
  String get selectPhotos => '选择照片';

  @override
  String get addPhotos => '继续添加照片';

  @override
  String get photoImportPrivacy => '照片仅复制到映见的本地项目中，不会因选择照片而上传云端。';

  @override
  String photoCount(int count) {
    return '$count/6';
  }

  @override
  String get photoLoadFailed => '无法读取这张照片';

  @override
  String get photoImportFailed => '照片导入失败，请重试';

  @override
  String get photoImportIssuesTitle => '部分照片未导入';

  @override
  String photoUnsupportedFormat(String name) {
    return '$name：格式暂不支持';
  }

  @override
  String photoAnimatedUnsupported(String name) {
    return '$name：暂不支持动态图片';
  }

  @override
  String photoFileTooLarge(String name) {
    return '$name：文件超过 100 MB';
  }

  @override
  String photoDimensionsTooLarge(String name) {
    return '$name：超过 48 MP 或最长边 12,000 px';
  }

  @override
  String photoUnreadable(String name) {
    return '$name：图片损坏或无法读取';
  }

  @override
  String photoCopyFailed(String name) {
    return '$name：无法创建本地工作副本';
  }

  @override
  String get photoLimitReached => '每个项目最多导入 6 张照片';

  @override
  String get projectRestoreFailed => '无法恢复上次项目';

  @override
  String get projectSaveFailed => '无法保存本次调整，请重试';

  @override
  String get removePhoto => '移除照片';

  @override
  String get removePhotoConfirmation => '仅删除映见项目中的本地副本，不影响系统相册原图。';

  @override
  String get deleteProject => '删除项目';

  @override
  String get deleteProjectConfirmation => '删除项目和映见保存的工作副本？系统相册原图不会被删除。';

  @override
  String get movePhotoEarlier => '向前移动';

  @override
  String get movePhotoLater => '向后移动';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get retry => '重试';

  @override
  String get exposure => '曝光';

  @override
  String get contrast => '对比度';

  @override
  String get warmth => '色温';

  @override
  String get exportOriginalQuality => '原画质导出';

  @override
  String photoExported(int width, int height) {
    return '已保存到系统相册（$width × $height）';
  }

  @override
  String get photoExportFailed => '导出失败，请检查相册权限后重试';

  @override
  String get unknownPageTitle => '页面不存在';

  @override
  String get unknownPageMessage => '暂时无法打开这个页面';

  @override
  String get settings => '设置';

  @override
  String get privacyAndDiagnostics => '隐私与诊断';

  @override
  String get anonymousDiagnostics => '匿名诊断';

  @override
  String get diagnosticsOffDescription => '默认关闭，不发送分析、崩溃或性能数据';

  @override
  String get diagnosticsOnDescription => '发送经过最小化处理的匿名诊断数据';

  @override
  String get diagnosticsUnavailableDescription => '尚未配置映见独立 Firebase 项目';

  @override
  String get diagnosticsEnableFailed => '诊断服务暂不可用，设置已保持关闭';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get privacyPolicyDescription => '查看照片、诊断与第三方数据处理说明';

  @override
  String get termsOfUse => '使用条款';

  @override
  String get rateApp => '去评分';

  @override
  String get rateAppDescription => '打开应用商店评分页面';

  @override
  String get storeListingUnavailable => '应用商店页面尚未配置';

  @override
  String get openSourceLicenses => '开源许可';

  @override
  String get legalDocumentLoadFailed => '暂时无法加载此文档';
}
