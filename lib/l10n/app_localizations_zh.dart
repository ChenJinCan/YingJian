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
  String get unfinishedProject => '未完成项目';

  @override
  String get continueLastEditing => '继续上次编辑';

  @override
  String get startNewProject => '开始新项目';

  @override
  String get deleteAndStartNew => '删除并新建';

  @override
  String get projectDeleteFailed => '无法删除本地项目，现有内容未改变。';

  @override
  String lastProjectSummary(int count, String date, String time) {
    return '$count 张照片 · 最后编辑于 $date $time';
  }

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
  String get compositionPreviewUnavailable => '构图预览暂不可用。可恢复原始构图或稍后重试；原图不受影响。';

  @override
  String get effectPreviewUnavailable => '当前效果预览暂不可用。可重置本次调整或稍后重试；原图不受影响。';

  @override
  String get recommendationPreviewUnavailable =>
      '这套推荐预览暂不可用。可重试或查看其他方向；原图不受影响。';

  @override
  String get photoImportCanceled => '未添加任何照片';

  @override
  String get importingPhotos => '正在本地导入照片…';

  @override
  String get restoringProject => '正在恢复本地项目…';

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
  String get highlights => '高光';

  @override
  String get shadows => '阴影';

  @override
  String get contrast => '对比度';

  @override
  String get warmth => '色温';

  @override
  String get tint => '色调';

  @override
  String get saturation => '饱和度';

  @override
  String get clarity => '清晰度';

  @override
  String get naturalPortraitRetouch => '自然精修';

  @override
  String get oneTapNaturalBeautification => '一键自然美化';

  @override
  String get applyNaturalBeautification => '应用自然美化';

  @override
  String get textureSmoothing => '质感磨皮';

  @override
  String get skinToneLighting => '肤色与面部光线';

  @override
  String get blemishReduction => '瑕疵减弱';

  @override
  String get faceSlim => '瘦脸';

  @override
  String get faceSlimBackgroundProtected => '为保护背景线条，这张照片暂不提供瘦脸';

  @override
  String get faceSlimMultipleFaces => '检测到多个人脸：自然精修可用，瘦脸仅支持单人照片';

  @override
  String get faceSlimUnavailable => '这张照片暂不满足安全瘦脸条件';

  @override
  String get faceSlimTargetHint => '选择要调整的人脸（按画面从左到右）';

  @override
  String faceSlimTarget(int number) {
    return '人脸 $number';
  }

  @override
  String get bodySlim => '瘦身';

  @override
  String get portraitTools => '人像';

  @override
  String get lightAndColorTools => '光色';

  @override
  String get localPortraitReady => '人像工具已就绪 · 本地处理';

  @override
  String get portraitToolsUnavailable => '当前照片未通过人像安全检测，仍可继续调整光色';

  @override
  String get switchToCurrentPhotoForPortrait => '切换到“当前照片”后可使用人像工具';

  @override
  String get resetCurrentAdjustment => '归零当前调整';

  @override
  String get composition => '构图';

  @override
  String get straighten => '水平校正';

  @override
  String get rotateLeft => '向左旋转';

  @override
  String get rotateRight => '向右旋转';

  @override
  String get originalCrop => '原始';

  @override
  String get cropSquare => '1:1';

  @override
  String get cropFourThree => '4:3';

  @override
  String get cropSixteenNine => '16:9';

  @override
  String get resetComposition => '恢复原始构图';

  @override
  String get compareOriginal => '查看原图';

  @override
  String get compareEdited => '返回效果';

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

  @override
  String get analysisPreparing => '正在本地准备三套效果…';

  @override
  String get recommendationsTitle => '先选一个整体方向';

  @override
  String get recommendationsSubtitle => '三套效果都在本机生成，不上传照片。选中后可继续细调。';

  @override
  String get safeFallbackNotice => '当前使用克制的安全配方；像素级分析能力完成质量验证后再启用。';

  @override
  String get localAnalysisNotice => '本机像素分析已为每张照片准备有边界的自适应调整。';

  @override
  String get localEffect => '本地效果';

  @override
  String get useThisLook => '使用这套效果';

  @override
  String get recommendationNaturalClean => '自然干净';

  @override
  String get recommendationAtmosphericColor => '氛围色彩';

  @override
  String get recommendationTexturedStyle => '质感风格';

  @override
  String get recommendationReasonBalancedFallback => '均衡克制的安全回退';

  @override
  String get recommendationReasonWarmFallback => '安全增加轻微暖意';

  @override
  String get recommendationReasonTexturedFallback => '克制增强质感，不激进锐化';

  @override
  String get recommendationReasonProtectsUncertain => '保守保护不确定输入';

  @override
  String get recommendationReasonProtectsTexture => '保留细节与局部反差';

  @override
  String get recommendationReasonCorrectsExposure => '平衡检测到的曝光';

  @override
  String get recommendationReasonCorrectsWhiteBalance => '修正检测到的偏色';

  @override
  String get editWholeGroup => '编辑整组';

  @override
  String get editCurrentPhoto => '仅当前照片';

  @override
  String photoPositionAndScope(int current, int total, String scope) {
    return '第 $current / $total 张 · $scope';
  }

  @override
  String get photoStatusUnprocessed => '未处理';

  @override
  String get photoStatusAutoCompensated => '自动补偿';

  @override
  String get photoStatusOverridden => '单张精修';

  @override
  String get photoStatusFailed => '处理失败';

  @override
  String get photoStatusQueued => '待导出';

  @override
  String batchExportPhotos(int count) {
    return '批量导出 $count 张';
  }

  @override
  String exportConfirmationMessage(int count) {
    return '将从每张只读原图生成 JPEG（sRGB，质量 95），共 $count 张，并保存到系统相册。';
  }

  @override
  String get startExport => '开始导出';

  @override
  String get syncCurrentAdjustments => '同步当前调整到整组';

  @override
  String get syncGroupConfirmationTitle => '将当前光色调整同步到整组？';

  @override
  String get syncGroupConfirmationMessage =>
      '曝光、色彩和质感会应用到全部照片；构图仍只保留在当前照片。这个操作可以撤销。';

  @override
  String get syncGroupAction => '同步整组';

  @override
  String get exportingPhotos => '正在逐张导出…';

  @override
  String get cancelExport => '取消未开始项';

  @override
  String exportSummary(int saved, int failed, int cancelled) {
    return '已保存 $saved 张 · 失败 $failed 张 · 取消 $cancelled 张';
  }

  @override
  String get retryFailedPhotos => '只重试失败与取消项';

  @override
  String get shareSavedPhotos => '分享已保存照片';

  @override
  String get sharingPhotos => '正在打开系统分享…';

  @override
  String get photoShareCompleted => '已通过系统分享完成操作';

  @override
  String get photoShareCanceled => '已取消分享，保存结果不受影响';

  @override
  String get photoShareFailed => '暂时无法分享，保存结果不受影响';

  @override
  String get continueEditing => '继续编辑';
}
