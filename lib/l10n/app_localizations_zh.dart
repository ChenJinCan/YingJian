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
  String get homeTagline => '一张照片，专注修好';

  @override
  String get startEditing => '开始修图';

  @override
  String get homeHeroTitle => '让变美更容易';

  @override
  String get homeSupporting => '选张照片，说说想怎么改';

  @override
  String get homePrimaryAction => '选择照片开始';

  @override
  String get homeChooseResult => '选择想得到的结果';

  @override
  String get imageApplication => '图片应用';

  @override
  String get imageApplicationSubtitle => '换一种完整风格';

  @override
  String get motionCreation => '动起来';

  @override
  String get motionCreationSubtitle => '生成自然动态作品';

  @override
  String get optimizePhoto => '优化照片';

  @override
  String get optimizePhotoSubtitle => '调亮、清晰、增强质感';

  @override
  String get homeChangeStyle => '换风格';

  @override
  String get changeStyleSubtitle => '日系、胶片、插画、电影感';

  @override
  String get removeBackgroundOrObjects => '去背景 / 去杂物';

  @override
  String get removeBackgroundOrObjectsSubtitle => '抠图、白底、清理路人杂物';

  @override
  String get createMotionEffect => '做动态效果';

  @override
  String get createMotionEffectSubtitle => '让静态照片自然动起来';

  @override
  String get preparingImage => '正在准备图片…';

  @override
  String get recentCreations => '最近创作';

  @override
  String get continueCreation => '继续创作';

  @override
  String get currentStyle => '当前风格';

  @override
  String get currentResult => '当前结果';

  @override
  String get chooseCapabilityTitle => '请选择能力';

  @override
  String get chooseCapabilityHint => '系统不会替你选择；每次只执行你点选的一项。';

  @override
  String get chooseAnotherCapability => '重新选择能力';

  @override
  String get capabilityUnavailable => '该能力尚未完成';

  @override
  String get capabilityUnavailableDetail =>
      '当前不会处理、上传、创建任务或扣费。你可以返回能力列表自己选择下一步。';

  @override
  String get cloudCapabilitiesNotLoaded => '云端能力待连接';

  @override
  String get cloudCapabilitiesNotLoadedDetail =>
      '尚未检查当前云端可用状态。点击重试只会连接并查询，不会上传、创建任务或扣费。';

  @override
  String get cloudCapabilitiesLoading => '正在连接云端能力';

  @override
  String get cloudCapabilitiesLoadingDetail => '正在查询当前能力状态，不会上传照片、创建任务或扣费。';

  @override
  String get cloudCapabilitiesConnectionFailed => '云端连接失败';

  @override
  String get cloudCapabilitiesConnectionFailedDetail =>
      '暂时无法确认当前能力状态。请检查网络后重试；不会自动上传、创建任务或扣费。';

  @override
  String get cloudCapabilityUnavailable => '该云端能力当前未开通';

  @override
  String get cloudCapabilityUnavailableDetail =>
      '服务端当前没有为这项能力提供可执行额度。不会上传、创建任务或扣费。';

  @override
  String get cloudReconciliationRequired => '云端任务状态待确认';

  @override
  String get cloudReconciliationRequiredDetail =>
      '上一次请求可能已被云端接收。已暂停新建云端任务并保留当前权益状态；只会查询原请求，不会重复生成或重复扣费。';

  @override
  String get checkCloudGenerationStatus => '查询原任务状态';

  @override
  String get capabilityOptimizeNatural => '自然优化';

  @override
  String get capabilityOptimizeAiRepair => 'AI 修复';

  @override
  String get capabilityOptimizeUpscale => '高清放大';

  @override
  String get capabilityOptimizeOldPhoto => '老照片修复';

  @override
  String get capabilityStyleOfficial => '官方风格';

  @override
  String get capabilityStyleText => '文字定风格';

  @override
  String get capabilityStyleVoice => '语音定风格';

  @override
  String get capabilityStyleReference => '参考图风格';

  @override
  String get capabilityStyleAiRedraw => 'AI 风格重绘';

  @override
  String get capabilityCleanupWhite => '人物白底';

  @override
  String get capabilityCleanupTransparent => '透明抠图';

  @override
  String get capabilityCleanupReplaceBackground => '替换背景';

  @override
  String get capabilityCleanupRemovePasserby => '去路人';

  @override
  String get capabilityCleanupBrushRemove => '涂抹去物';

  @override
  String get capabilityMotionSubtle => '轻微动态';

  @override
  String get capabilityMotionCameraPush => '镜头推进';

  @override
  String get capabilityMotionLightFlow => '光影流动';

  @override
  String get capabilityMotionAiNatural => 'AI 自然动效';

  @override
  String get capabilityOptimizeNaturalDescription => '本地改善亮度、清晰度和质感，原图保持不变。';

  @override
  String get capabilityOptimizeAiRepairDescription => '修复模糊、噪点和细节缺失。';

  @override
  String get capabilityOptimizeUpscaleDescription => '提升分辨率并保留主体细节。';

  @override
  String get capabilityOptimizeOldPhotoDescription => '修复划痕、褪色和老照片损伤。';

  @override
  String get capabilityStyleOfficialDescription => '从内置可复现风格中明确选择一种。';

  @override
  String get capabilityStyleTextDescription => '根据你输入的文字定义风格。';

  @override
  String get capabilityStyleVoiceDescription => '根据你确认的语音转写定义风格。';

  @override
  String get capabilityStyleReferenceDescription => '将参考图的光色质感应用到当前照片。';

  @override
  String get capabilityStyleAiRedrawDescription => '生成重新绘制的风格化静态图片。';

  @override
  String get capabilityCleanupWhiteDescription => '识别人像主体并生成白色背景。';

  @override
  String get capabilityCleanupTransparentDescription => '抠出主体并生成透明背景图片。';

  @override
  String get capabilityCleanupReplaceBackgroundDescription => '抠出主体后使用你选择的新背景。';

  @override
  String get capabilityCleanupRemovePasserbyDescription => '移除画面中的路人并补全背景。';

  @override
  String get capabilityCleanupBrushRemoveDescription => '只移除你明确涂抹标记的内容。';

  @override
  String get capabilityMotionSubtleDescription => '为整张照片添加幅度克制的平移与缩放动态。';

  @override
  String get capabilityMotionCameraPushDescription => '生成镜头缓慢推进的动态效果。';

  @override
  String get capabilityMotionLightFlowDescription => '生成光影自然流动的动态效果。';

  @override
  String get capabilityMotionAiNaturalDescription => '将照片上传到云端并生成 3 秒自然动态视频。';

  @override
  String get chooseUpscaleScale => '选择放大倍率';

  @override
  String get generateUpscale => '生成高清图片';

  @override
  String get generatingResult => '正在生成…';

  @override
  String get upscaleReady => '高清图片已生成，可分享或保存。';

  @override
  String get generateMotion => '生成动态照片';

  @override
  String get motionReady => '动态照片已生成，可分享或保存。';

  @override
  String get generationFailed => '生成失败，请重试。';

  @override
  String get generationConcurrencyExceeded => '已有云端任务仍在处理或待确认，暂时不能创建新的云端任务。';

  @override
  String get generationCreditExhausted => '当前云端权益不足，任务没有开始。';

  @override
  String get generationCapabilityDisabled => '该云端能力当前未开通，任务没有开始。';

  @override
  String get generationProviderFailed => '云端供应商处理失败，请保留当前结果后再决定是否重试。';

  @override
  String get cloudGenerationConsentTitle => '确认云端处理';

  @override
  String get cloudGenerationConsentDetail =>
      '确认后才会上传并创建这一项任务；处理可能需要等待，可取消阶段会显示取消操作。源图、蒙版和云端结果在网关最多保留 24 小时。';

  @override
  String get cloudUploadConsent => '同意上传当前照片完成所选能力';

  @override
  String cloudCostConsent(int creditCost) {
    return '确认消耗 $creditCost 次云端权益';
  }

  @override
  String get confirmAndGenerate => '确认并生成';

  @override
  String get confirmCloudGeneration => '开始云端处理';

  @override
  String get cloudGenerationReady => '云端处理结果已生成，可分享或保存。';

  @override
  String get cloudGenerationQueued => '任务已创建，正在等待云端处理。';

  @override
  String get cloudGenerationRunning => '云端正在处理所选能力。';

  @override
  String get cancelGeneration => '取消这次处理';

  @override
  String get generationCancelled => '这次处理已取消，原图和已有结果没有改变。';

  @override
  String get generationCancelledCreditReleased =>
      '这次处理已取消，本次权益已释放；原图和已有结果没有改变。';

  @override
  String get generationCancellationStillRunning =>
      '供应商已经开始处理，无法取消；同一任务继续运行，权益仍暂时占用。';

  @override
  String get generationStatusCreditHeld =>
      '处理结果仍需确认，权益暂时保留。请刷新同一任务，不会新建任务或再次扣费。';

  @override
  String get previewMotionResult => '播放动态结果';

  @override
  String get chooseOldPhotoColorMode => '选择老照片的颜色处理';

  @override
  String get oldPhotoPreserveColor => '保留原有色彩';

  @override
  String get oldPhotoColorize => '智能上色';

  @override
  String get aiRedrawDefinitionLabel => '描述要重绘成什么风格';

  @override
  String get aiRedrawDefinitionHint => '例如：保留人物身份，改成低饱和电影剧照';

  @override
  String get aiRedrawDefinitionSummary => '只按你确认的生成意图重绘，不会自动改成其他方向。';

  @override
  String get aiRedrawConfirmIntent => '确认生成意图';

  @override
  String get aiRedrawIntentPreviewTitle => '生成意图';

  @override
  String get aiRedrawIntentConfirmed => '已冻结这份定义；修改文字后需要重新确认。';

  @override
  String aiRedrawIntentVersion(int revision) {
    return '定义版本 $revision';
  }

  @override
  String get aiRedrawIntentInvalid => '请输入 1 至 500 个可见字符，不能包含隐藏或控制字符。';

  @override
  String get markRemovalArea => '涂抹要移除的区域';

  @override
  String get changeRemovalArea => '重新涂抹区域';

  @override
  String get removalAreaReady => '已使用你手动涂抹的区域，不会自动选择其他内容。';

  @override
  String get applyNaturalOptimization => '应用自然优化';

  @override
  String get applyWhiteBackground => '应用白底';

  @override
  String get applyTransparentBackground => '生成透明抠图';

  @override
  String get applyReplacementBackground => '应用新背景';

  @override
  String get chooseReplacementBackground => '选择新背景';

  @override
  String get chooseAnotherBackground => '更换背景图片';

  @override
  String get importingBackground => '正在导入背景…';

  @override
  String get optimizeResult => '自动优化';

  @override
  String get cleanupResult => '白底清理';

  @override
  String get optimizeApplied => '照片已优化';

  @override
  String get cleanupApplied => '清理已应用';

  @override
  String get optimizeAgain => '重新优化';

  @override
  String get cleanupAgain => '继续清理';

  @override
  String get cleanupWhiteBackgroundUnavailable => '暂未识别到可安全处理的主体，本次人物白底不会执行。';

  @override
  String get cleanupSubjectUnavailable => '暂未识别到可安全处理的主体，本次背景处理不会执行。';

  @override
  String get localStaticTaskIosOnly => '该本地处理当前仅支持 iPhone。';

  @override
  String get aiDefineStyle => 'AI 定风格';

  @override
  String get describeStyleTitle => '描述你的风格';

  @override
  String get describeStyleHint => '例如：雨后的电影感，人物保持自然';

  @override
  String get styleDefinitionInputHint => '可用文字、确认后的语音转写或单独的参考图定义风格；源照片始终是结果主体。';

  @override
  String get styleInputText => '文字';

  @override
  String get styleInputVoice => '语音';

  @override
  String get styleInputReference => '参考图';

  @override
  String get styleVoiceTranscriptHint => '先说出你的想法，再确认或修改转写内容后定义风格。';

  @override
  String get styleVoiceRecord => '开始录音';

  @override
  String get styleVoiceStop => '停止录音';

  @override
  String get styleVoiceListening => '正在聆听…';

  @override
  String get styleVoiceFailed => '语音暂未转写成功。当前图片和输入均已保留。';

  @override
  String get styleReferenceHint => '单独选择一张参考图。只提取色彩、光线、质感和氛围，不复制人物、物体、文字或构图。';

  @override
  String get styleReferenceChoose => '选择参考图';

  @override
  String get styleReferenceSource => '源照片';

  @override
  String get styleReferenceImage => '风格参考';

  @override
  String get styleReferenceRemove => '移除参考图';

  @override
  String get styleReferenceKeptLocal => '参考图不会替换源照片；风格定义完成后会移除本地临时副本。';

  @override
  String get styleReferenceUnavailable => '当前设备无法使用参考图。当前图片保持不变。';

  @override
  String get styleReferenceFailed => '这张参考图暂时无法使用，源照片和当前风格均未改变。';

  @override
  String get defineStyle => '定义风格';

  @override
  String get styleNotUnderstood => '暂时没理解。试试“电影感”“暖一点”或“清冷一点”。';

  @override
  String get styleAiCustom => 'AI 风格';

  @override
  String get styleSavedCustom => '已保存风格';

  @override
  String get styleOfficialDefinitionSummary => '固定且可复现的本地风格。';

  @override
  String get styleTextDefinitionSummary => '根据你确认的文字描述生成的本地风格。';

  @override
  String get styleVoiceDefinitionSummary => '根据你确认的语音转写生成的本地风格。';

  @override
  String get styleReferenceDefinitionSummary => '只使用参考图的色彩、光线、质感与氛围生成的本地风格。';

  @override
  String get styleReferenceWarmTitle => '暖调参考';

  @override
  String get styleReferenceCoolTitle => '冷调参考';

  @override
  String get styleReferenceNaturalTitle => '自然参考';

  @override
  String get styleNatural => '自然';

  @override
  String get styleSoftLight => '柔光';

  @override
  String get styleNight => '夜色';

  @override
  String get styleCool => '清冷';

  @override
  String get styleWarmSun => '暖阳';

  @override
  String get styleMono => '黑白';

  @override
  String get styleBreeze => '微风';

  @override
  String get styleBreathe => '呼吸';

  @override
  String get stylePushIn => '推进';

  @override
  String get styleFlowingLight => '流光';

  @override
  String get styleCinema => '电影';

  @override
  String get applyStyle => '应用风格';

  @override
  String get applyingStyle => '正在应用…';

  @override
  String get styleApplied => '风格已应用';

  @override
  String get changeStyle => '换个风格';

  @override
  String get motionConfirmationTitle => '生成动态作品';

  @override
  String get motionConfirmationBody =>
      '确认后才会上传这张图片并创建动态任务。当前工程切片尚未接入生成服务，不会上传或消耗权益。';

  @override
  String get motionUnavailable => '动态生成服务尚未接入';

  @override
  String get motionUnavailableDetail => '当前不会上传图片、创建任务或消耗额度。你可以返回能力列表或首页。';

  @override
  String get gotIt => '知道了';

  @override
  String get onboardingPromise => '选一张照片，再说出你想要的感觉。映见专注把这一张修好。';

  @override
  String get onboardingContinue => '开始使用';

  @override
  String get onboardingSaveFailed => '暂时无法保存首次使用状态，请重试。';

  @override
  String get recentProjects => '最近项目';

  @override
  String get otherDrafts => '其他草稿';

  @override
  String get selectNewPhoto => '选择新照片';

  @override
  String get deleteDraft => '删除草稿';

  @override
  String get draftDeleteConfirmation =>
      '会删除映见中的草稿、生成结果，并取消仍可取消的云端任务；不会删除系统相册原图。云端任务已无法取消时，本次不会删除。';

  @override
  String get draftStatusEditing => '编辑中';

  @override
  String get draftStatusExported => '已导出';

  @override
  String get draftStatusModified => '有新修改';

  @override
  String get draftStatusNeedsUpdate => '需要更新';

  @override
  String get draftStatusNeedsRecovery => '需要恢复';

  @override
  String lastEditedAt(String date, String time) {
    return '最后编辑于 $date $time';
  }

  @override
  String get noRecentProjects => '还没有项目，选一张照片开始吧';

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
  String get projectDeleteCloudTaskActive =>
      '云端任务已经开始且暂时无法取消；为保留任务与权益状态，本次没有删除创作。';

  @override
  String get projectDeletedGenerationCleanupPending =>
      '创作已删除，但本地生成缓存尚未清理完成。系统相册内容不受影响。';

  @override
  String lastProjectSummary(int count, String date, String time) {
    return '1 张照片 · 最后编辑于 $date $time';
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
  String get preparingStylePreview => '正在准备风格预览';

  @override
  String get stylePreviewReady => '风格预览已就绪';

  @override
  String get stylePreviewFailedShowingOriginal => '风格预览失败，已保留当前画面';

  @override
  String get restorePreviousResult => '返回上次成片';

  @override
  String get selectPhotosTitle => '选择一张照片';

  @override
  String get selectPhotos => '选择照片';

  @override
  String get photoLoadFailed => '无法读取这张照片';

  @override
  String get compositionPreviewUnavailable => '构图预览暂不可用，可恢复原始构图或稍后重试。';

  @override
  String get effectPreviewUnavailable => '当前效果预览暂不可用，请重试。';

  @override
  String get photoImportCanceled => '未添加任何照片';

  @override
  String get importingPhotos => '正在导入照片…';

  @override
  String get preparingPhoto => '正在准备照片…';

  @override
  String get restoringProject => '正在恢复项目…';

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
  String get photoLimitReached => '当前项目已有一张照片';

  @override
  String get projectRestoreFailed => '无法恢复上次项目';

  @override
  String get taskRouteMismatch => '这个草稿不属于当前任务，请返回首页继续。';

  @override
  String get projectSaveFailed => '无法保存本次调整，请重试';

  @override
  String get editSavePending => '正在保存本次调整';

  @override
  String get editSaveRecoveryMessage => '本次调整尚未保存，当前仍显示上次安全结果。';

  @override
  String get discardAdjustment => '放弃本次调整';

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
  String get applyNaturalBeautification => '自然美化';

  @override
  String get textureSmoothing => '质感磨皮';

  @override
  String get skinToneLighting => '肤色与面部光线';

  @override
  String get blemishReduction => '瑕疵减弱';

  @override
  String get faceSlim => '瘦脸';

  @override
  String get faceSlimBackgroundProtected => '当前画面的背景线条与面部区域重叠，瘦脸暂不生效';

  @override
  String get faceSlimMultipleFaces => '检测到多个人脸，请选择要调整的人物';

  @override
  String get faceSlimUnavailable => '暂未识别到可调整的面部，瘦脸不会生效';

  @override
  String get faceSlimTargetHint => '选择要调整的人脸（按画面从左到右）';

  @override
  String faceSlimTarget(int number) {
    return '人脸 $number';
  }

  @override
  String get bodySlim => '瘦身';

  @override
  String get bodyToolsUnavailable => '暂未识别到可调整的人物，身形调整不会生效';

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
  String get semanticTools => '背景';

  @override
  String get mobileToolRetouch => '人像';

  @override
  String get semanticToolsLocalReady => '可以调整背景';

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
  String get lightAndColorTools => '光线';

  @override
  String get localPortraitReady => '可以调整人像';

  @override
  String get portraitToolsUnavailable => '暂未识别到可调整的人像，人像效果不会生效';

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
  String get shareResult => '分享成片';

  @override
  String get preparingShare => '正在准备分享…';

  @override
  String get sharingPhotos => '正在打开系统分享…';

  @override
  String get photoShareCompleted => '已通过系统分享完成操作';

  @override
  String get photoShareCanceled => '已取消分享，成片仍已保存到系统相册';

  @override
  String get photoShareFailed => '暂时无法分享，成片仍已保存到系统相册';

  @override
  String get photoResultShareCanceled => '已取消分享';

  @override
  String get photoResultShareFailed => '暂时无法分享，请重试';

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
  String get filterAndHsl => '颜色';

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
  String get quickNatural => '自然一点';

  @override
  String get quickBrighten => '亮一点';

  @override
  String get quickAtmosphere => '换氛围';

  @override
  String get quickEditBrighter => '更亮一点';

  @override
  String get quickEditNaturalSkin => '肤色自然一点';

  @override
  String get quickEditAtmosphere => '整体更有氛围';

  @override
  String get quickEditSoftBackground => '背景柔和一点';

  @override
  String get onlyEditThisPhoto => '只改这张';

  @override
  String get syncToAllPhotos => '同步到全部';

  @override
  String get manualAdjustments => '手动调整';

  @override
  String get manualAdjustmentsHint => '需要时再展开全部参数';

  @override
  String get adjustPhoto => '自己调';

  @override
  String get quickAdjust => '快速调整';

  @override
  String get allTools => '更多';

  @override
  String get metaOpSearchHint => '搜索调整能力';

  @override
  String get metaOpSearchNoResults => '没有找到可用能力';

  @override
  String get savePhotos => '导出';

  @override
  String get preparingExport => '正在准备成片…';

  @override
  String get canvasInteractionHint => '点按全屏 · 长按看原图';

  @override
  String get savingToSystemPhotos => '正在保存到系统相册…';

  @override
  String get savedToSystemPhotos => '已保存到系统相册';

  @override
  String get exportFailedTitle => '暂时无法导出';

  @override
  String get photoPermissionPurpose => '映见需要添加照片权限，才能把成片保存到系统相册。';

  @override
  String get goToSystemSettings => '前往系统设置';

  @override
  String get saveOptionsTitle => '完成优化';

  @override
  String get saveOptionsSubtitle => '选择要保存的照片';

  @override
  String get saveToAlbum => '保存到相册';

  @override
  String savingProgress(int current, int total) {
    return '正在保存 $current/$total';
  }

  @override
  String photoNumber(int number) {
    return '第 $number 张';
  }

  @override
  String get cancelRemainingPhotos => '取消剩余照片';

  @override
  String get savedPhotosAreKept => '已经保存的照片会保留';

  @override
  String partialSaveTitle(int saved, int failed) {
    return '已保存 $saved 张，$failed 张暂未保存';
  }

  @override
  String get photoLibraryTemporarilyUnavailable => '相册暂时无法写入';

  @override
  String retryPhotoCount(int count) {
    return '重试这 $count 张';
  }

  @override
  String get viewSavedPhotos => '查看已保存';

  @override
  String get backToEditing => '回到编辑';

  @override
  String get voiceEditTitle => '想怎么改？';

  @override
  String get voiceEditHint => '例如：照片亮一点，皮肤自然一点';

  @override
  String get voiceEditRecord => '开始说话';

  @override
  String get voiceEditStop => '完成录音';

  @override
  String get voiceEditListening => '正在听…';

  @override
  String get voiceEditApply => '应用修改';

  @override
  String get voiceEditUnsupported => '还没理解这条调整。可以换种说法，或直接手动调整。';

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
  String get editApplied => '已应用';

  @override
  String get manualSimpleHint => '选一个你想要的结果';

  @override
  String get manualBrighter => '亮一点';

  @override
  String get manualWarmer => '暖一点';

  @override
  String get manualMoreVivid => '鲜艳一点';

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
  String saveSuccess(int count) {
    return '已保存 $count 张照片';
  }

  @override
  String get finish => '完成';

  @override
  String get close => '关闭';

  @override
  String get fullscreenPreview => '全屏查看';

  @override
  String get fullscreenAdjusted => '调整后';

  @override
  String get fullscreenPreviewHint => '轻点返回调整 · 按住看原图';

  @override
  String get projectRequiresUpdateTitle => '需要更新后继续编辑';

  @override
  String get projectRequiresUpdateMessage =>
      '这组照片包含当前版本尚不支持的效果。已完整保留，只能查看，更新应用后可继续编辑和保存。';

  @override
  String get visualTracksTitle => '视觉轨道';

  @override
  String get visualTracksEntry => '视觉轨道';

  @override
  String get visualTracksNotApplied => '没有应用这次变化';

  @override
  String get eraAtmosphereTrack => '时代氛围';

  @override
  String get lightingTrack => '光照';

  @override
  String get vintageFilm => '复古胶片';

  @override
  String get currentEffect => '当前效果';

  @override
  String get nearFuture => '近未来';

  @override
  String get lightingNeedsPerson => '暂未识别到可调整光照的人物，其他光色工具仍可使用';

  @override
  String personNumber(int number) {
    return '人物 $number';
  }

  @override
  String get leftLight => '左侧光';

  @override
  String get frontLight => '正面光';

  @override
  String get rightLight => '右侧光';
}
