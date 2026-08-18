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
  String get homeHeroTitle => '让变美更容易';

  @override
  String get homeSupporting => '选几张照片，说出你想要的感觉。映见会先修好一张，再让整组自然统一。';

  @override
  String get homePrimaryAction => '选择照片开始';

  @override
  String get homeStepChoose => '选照片';

  @override
  String get homeStepDescribe => '说想法';

  @override
  String get homeStepSave => '存整组';

  @override
  String get homeGuideSemantics => '使用步骤：选照片，说想法，保存整组';

  @override
  String get onboardingPromise => '先选照片，再说出你想要的感觉。映见会把一张修好，也让整组自然统一。';

  @override
  String get onboardingPrivacy => '默认在手机本地处理，不会上传你的照片';

  @override
  String get onboardingContinue => '开始使用';

  @override
  String get onboardingSaveFailed => '暂时无法保存首次使用状态，请重试。';

  @override
  String get recentProjects => '最近项目';

  @override
  String get noRecentProjects => '还没有项目，选几张照片开始吧';

  @override
  String get unfinishedProject => '未完成项目';

  @override
  String get continueLastEditing => '继续上次编辑';

  @override
  String get openProject => '打开项目';

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
  String get qualityImprovement => '画质改善';

  @override
  String get applyQualityImprovement => '一键改善画质';

  @override
  String get noiseReduction => '去噪';

  @override
  String get lowLightRecovery => '暗光提亮';

  @override
  String get hazeRemoval => '去灰';

  @override
  String get detailSharpening => '细节锐化';

  @override
  String get qualityTools => '画质';

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
  String get faceSlimMultipleFaces => '检测到多个人脸，请选择要调整的人物';

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
  String get headSize => '小头';

  @override
  String get jaw => '下颌';

  @override
  String get chin => '下巴';

  @override
  String get eyes => '眼睛';

  @override
  String get nose => '鼻子';

  @override
  String get mouth => '嘴型';

  @override
  String get heightAdjustment => '增高';

  @override
  String get shoulders => '肩宽';

  @override
  String get waist => '腰围';

  @override
  String get legs => '长腿';

  @override
  String get bodyTargetHint => '选择要调整的人物（按画面从左到右）';

  @override
  String bodyTarget(int number) {
    return '人物 $number';
  }

  @override
  String get semanticTools => '主体与局部';

  @override
  String get mobileToolRetouch => '精修';

  @override
  String get semanticToolsLocalReady => '主体分割已就绪 · 本地处理';

  @override
  String get refineSubjectMask => '修整主体边缘';

  @override
  String get subjectMask => '主体蒙版';

  @override
  String get localAdjustment => '局部光色';

  @override
  String get localExposure => '局部曝光';

  @override
  String get localSaturation => '局部饱和度';

  @override
  String get paintMask => '涂抹';

  @override
  String get eraseMask => '擦除';

  @override
  String get maskBrushHint => '在画面上涂抹需要生效的区域；切换擦除可恢复该区域。绿色为添加，红色为擦除。';

  @override
  String get clearMask => '清空蒙版';

  @override
  String get semanticSubjectUnavailable => '未识别到可用主体；仍可使用消除笔';

  @override
  String get backgroundTreatment => '背景处理';

  @override
  String get backgroundOriginal => '原背景';

  @override
  String get backgroundBlur => '背景虚化';

  @override
  String get backgroundWhite => '白色背景';

  @override
  String get backgroundBlack => '黑色背景';

  @override
  String get backgroundWarm => '暖色背景';

  @override
  String get backgroundCool => '冷色背景';

  @override
  String get backgroundImage => '图片背景';

  @override
  String get backgroundImageImportFailed => '背景图片无法导入，请换一张重试。';

  @override
  String get subjectExposure => '主体明暗';

  @override
  String get subjectSaturation => '主体饱和';

  @override
  String get backgroundExposure => '背景明暗';

  @override
  String get backgroundSaturation => '背景饱和';

  @override
  String get eraseBrush => '消除笔';

  @override
  String get eraseBrushHint => '在要移除的区域上涂抹；使用周围纹理进行本地修补';

  @override
  String get brushSize => '笔刷大小';

  @override
  String get clearEraseStrokes => '清除全部消除笔画';

  @override
  String get clear => '清除';

  @override
  String get apply => '应用';

  @override
  String get portraitTools => '人像';

  @override
  String get lightAndColorTools => '光色';

  @override
  String get groupStyleIntensity => '整组风格';

  @override
  String get groupStyleIntensityHint => '调整整组共享效果强度，同时保留每张照片的独立补偿。';

  @override
  String get primaryRecommendation => '主推荐';

  @override
  String get alternativeRecommendation => '备选';

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
  String get freeCrop => '自由裁剪';

  @override
  String get freeCropHint => '拖动裁剪框的角点，保留想要的画面';

  @override
  String get applyCrop => '应用裁剪';

  @override
  String get cropFourThree => '4:3';

  @override
  String get cropThreeFour => '3:4';

  @override
  String get cropSixteenNine => '16:9';

  @override
  String get cropNineSixteen => '9:16';

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
  String get recommendationsTitle => '选一个喜欢的方向';

  @override
  String get recommendationsSubtitle => '三套效果都在本机生成，不上传照片。先看结果，之后随时都能继续修改。';

  @override
  String get safeFallbackNotice => '当前使用克制的安全配方；像素级分析能力完成质量验证后再启用。';

  @override
  String get localAnalysisNotice => '本机像素分析已为每张照片准备有边界的自适应调整。';

  @override
  String get localEffect => '本地效果';

  @override
  String get useThisLook => '就用这个';

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
  String get photoStatusExporting => '导出中';

  @override
  String get photoStatusExported => '已导出';

  @override
  String get photoStatusExportFailed => '导出失败';

  @override
  String get photoStatusExportCancelled => '已取消导出';

  @override
  String batchExportPhotos(int count) {
    return '批量导出 $count 张';
  }

  @override
  String exportConfirmationMessage(int count) {
    return '将从 $count 张只读原图重新执行全部效果并保存到系统相册。';
  }

  @override
  String get exportPhotoPlan => '本次照片';

  @override
  String get exportWillExport => '将导出';

  @override
  String get exportWithSafeFallback => '将以安全回退导出';

  @override
  String get exportProcessingEstimate => '预计逐张本地处理，可取消尚未开始的照片。';

  @override
  String get startExport => '开始导出';

  @override
  String get exportFormat => '格式';

  @override
  String get exportFormatJpeg => 'JPEG';

  @override
  String get exportFormatHeif => 'HEIF';

  @override
  String get exportSize => '输出尺寸';

  @override
  String get exportSizeOriginal => '原像素尺寸';

  @override
  String get exportQuality => '画质';

  @override
  String get exportQualityHigh => '高画质';

  @override
  String get exportQualityStandard => '标准';

  @override
  String get exportQualityCompact => '节省空间';

  @override
  String get exportColorSpaceNotice => '首版统一以 sRGB 输出；原图不会被覆盖。';

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

  @override
  String get flipHorizontal => '水平翻转';

  @override
  String get flipVertical => '垂直翻转';

  @override
  String get perspectiveHorizontal => '水平透视';

  @override
  String get perspectiveVertical => '垂直透视';

  @override
  String get filterAndHsl => '滤镜与 HSL';

  @override
  String get filterStrength => '滤镜强度';

  @override
  String get hslHue => '色相';

  @override
  String get hslSaturation => '饱和度';

  @override
  String get hslLightness => '明度';

  @override
  String get hslRed => '红';

  @override
  String get hslOrange => '橙';

  @override
  String get hslYellow => '黄';

  @override
  String get hslGreen => '绿';

  @override
  String get hslCyan => '青';

  @override
  String get hslBlue => '蓝';

  @override
  String get hslPurple => '紫';

  @override
  String get hslMagenta => '洋红';

  @override
  String get filterNone => '原图';

  @override
  String get filterClean => '清透';

  @override
  String get filterPortrait => '人像';

  @override
  String get filterCinematic => '电影';

  @override
  String get filterFilm => '胶片';

  @override
  String get filterWarmSun => '暖阳';

  @override
  String get filterCoolAir => '冷空气';

  @override
  String get filterVivid => '鲜明';

  @override
  String get filterFaded => '褪色';

  @override
  String get filterNoir => '黑白';

  @override
  String get filterFood => '美食';

  @override
  String get filterLandscape => '风景';

  @override
  String get filterNight => '夜景';

  @override
  String get voiceEditEntry => '说说怎么修';

  @override
  String get voiceEditPrompt => '还想怎么改？';

  @override
  String get quickEditBrighter => '更亮一点';

  @override
  String get quickEditNaturalSkin => '肤色自然一点';

  @override
  String get manualAdjustments => '手动调整';

  @override
  String get manualAdjustmentsHint => '需要时再展开全部参数';

  @override
  String get adjustPhoto => '自己调';

  @override
  String get quickAdjust => '快速调整';

  @override
  String get allTools => '全部工具';

  @override
  String get savePhotos => '保存';

  @override
  String get voiceEditTitle => '想怎么改？';

  @override
  String get voiceEditHint => '例如：照片亮一点，皮肤自然一点';

  @override
  String get voiceEditPrivacy => '语音只用于转写指令；修图结果仍由可见参数在本地生成。';

  @override
  String get voiceEditRecord => '开始说话';

  @override
  String get voiceEditStop => '完成录音';

  @override
  String get voiceEditListening => '正在听…';

  @override
  String get voiceEditApply => '应用修改';

  @override
  String get voiceEditUnsupported => '暂时无法安全理解这条指令，请换一种说法或手动调整。';

  @override
  String get voiceEditFailed => '暂时无法使用语音，可以直接输入文字。';

  @override
  String voiceEditApplied(int count) {
    return '已应用 $count 项可见参数';
  }

  @override
  String get voiceEditDone => '已经改好了';

  @override
  String get editResultBrighter => '已让这张更亮';

  @override
  String get editResultApplied => '已完成这次修改';

  @override
  String get syncAllPhotos => '同步到全部';

  @override
  String get manualSimpleHint => '选一个你想要的结果';

  @override
  String get manualBrighter => '亮一点';

  @override
  String get manualWarmer => '暖一点';

  @override
  String get manualNaturalSkin => '自然肤色';

  @override
  String get manualSmootherSkin => '皮肤更细腻';

  @override
  String get manualSmallerFace => '脸小一点';

  @override
  String get manualNaturalBody => '身形更自然';

  @override
  String get choosePersonTitle => '想修谁？';

  @override
  String get choosePersonHint => '点一下照片里的人';

  @override
  String saveAllPhotos(int count) {
    return '保存全部 $count 张';
  }

  @override
  String get saveCurrentPhoto => '保存当前 1 张';

  @override
  String saveSuccess(int count) {
    return '$count 张照片已保存到相册';
  }

  @override
  String get finish => '完成';
}
