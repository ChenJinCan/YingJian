# 映见 MVP Spec

> 状态：ready-for-agent；版本：1.4；日期：2026-08-09；核心承诺：一张精修，整组好看；首发平台：iOS / TestFlight；本轮目标：交付无需借助其他应用即可完成构图、调色、滤镜、画质改善、自然人像精修、基础五官与身体塑形、简单局部处理和高质量导出的静态修图闭环，再验证“三套本地推荐 + 整组自适应 + 批量保真导出”。

## Problem Statement

用户准备发布一张或一组照片时，通常知道自己想要“自然、干净、有氛围、适合发出来”，但不知道应该选择什么工具、滤镜和参数。传统全能编辑器提供大量能力，却把决策和重复劳动留给用户；固定滤镜产品路径很短，但难以修复具体问题；纯生成式 AI 操作简单，却存在等待、成本、身份漂移和不可控修改。

对于人像，用户说的“精修”和“变美”不是一个综合磨皮滑杆。竞品入场能力至少包括：直接给出第一结果的一键自然美化、可独立控制的质感磨皮、肤色与面部光线、自动瑕疵减弱，以及本人显式选择的克制瘦脸与瘦身。只做人像识别、全局色彩、单一磨皮或只有工具入口，都不能构成最低可用的人像修图能力。

对于一组照片，问题更明显：用户需要重复修每一张，又希望其中最重要的照片可以进一步精修。现有映见代码虽已具备部分导入、基础编辑和导出能力，但尚未证明自然人像、瘦脸、瘦身、整组一致性和批量导出的完整用户闭环达到竞品入场基线。

## Solution

映见让用户先选择结果，再逐步展开工具。

用户无需登录即可导入 1–6 张照片。应用在本地分析照片的基础质量、主体、人脸和光线，为单张或整组生成三套差异明确、可即时预览的本地推荐方案。用户选择一个方向后，可以调整整组强度，也可以进入任意重点照片做基础光色、构图、画质改善和六项人像核心能力。

重点照片提供本地“画质改善”入口。它把去噪、暗光提亮、去灰和细节锐化的安全推荐值写入四个真实参数，用户可以独立调整、归零和撤销；首版只改善已有像素，不执行超分辨率、生成式细节重建或人脸生成修复。

`一键自然美化`是一项把安全推荐值写入真实子参数的语义操作，不是第四层隐藏效果。它展开后明确显示 `质感磨皮`、`肤色与面部光线`、`瑕疵减弱`；项目保存这三个非几何参数、最多三张脸各自独立的面部塑形参数、最多三个可用身体主体的独立塑形参数和算法版本。多人照片由用户显式选择目标；应用不做年龄或性别推断。所有几何参数默认值为 `0`，不由一键自然美化或三套推荐自动开启。整组共享审美风格，每张照片保留独立补偿和单张覆盖，最终从原图批量导出。

默认闭环完全本地执行，不上传照片、不调用图片生成模型、不要求账号，也不依赖云端服务成功。

### 首发平台边界

- 本轮 MVP 的实现、样片、真机、无障碍、性能、候选和交付门只要求 iOS 闭环成立，最终交付到 TestFlight。
- Flutter domain/application、项目文件和版本化配方继续保持跨平台；已有 Android 代码和证据保留，但 Android 构建、ADB、设备矩阵、商店交付和跨端画质对齐不再阻断本轮 MVP。
- 本轮不得因为 Android 尚未验证而阻断 iOS TestFlight，也不得把 iOS 通过外推成 Android 已完成。恢复 Android 验证时另开后续里程碑并重新冻结其设备与质量门。

```text
导入 1–6 张
    ↓
本地分析与安全回退
    ↓
三套本地推荐
    ↓
选择整组方向
    ↓
整组调整 ⇄ 重点照片光色/构图/一键自然美化及精调/瘦脸/瘦身
    ↓
逐张检查
    ↓
原画质批量导出
```

## MVP Success Definition

### 单次成功会话

一次成功会话必须同时满足：

1. 导入至少一张有效照片。
2. 在限定时间内显示三套可用的本地方案，或在分析失败时显示三套安全回退方案。
3. 用户主动选择一个方案。
4. 用户可以进入编辑并保持所有操作可撤销。
5. 至少一张照片从原图成功导出。
6. 默认流程没有创建云端图片任务。

### 人像场景成功条件

对满足安全门的已有成人图片，人像 MVP 必须同时满足：

1. 首层提供 `一键自然美化`、`瘦脸`、`瘦身`；一键结果可展开为 `质感磨皮`、`肤色与面部光线`、`瑕疵减弱`三个真实子参数，不允许隐藏基线效果。
2. 一键自然美化可以随用户选择推荐方案写入三个非几何参数；瘦脸和瘦身默认均为 `0`，只在用户主动滑动后改变。
3. 质感磨皮减少粗糙和不均匀但保留毛孔趋势、五官、发际线、胡须和身份纹理；肤色与面部光线改善色偏、暗沉和阴影但不漂白或破坏场景光线。
4. 瑕疵减弱只处理高置信度、孤立、短期性的小范围痘印和色斑；无法区分痣、雀斑、皱纹、妆容或身份特征时必须跳过。
5. 非几何能力支持最多三张高置信度成人脸，每张脸独立计算安全上限；低置信度对象独立关闭，不阻断其他人物、基础修图或导出。
6. 用户可在最多三张可用人脸中逐脸选择并设置独立强度；非零瘦脸只收窄目标脸部轮廓，同时保护其他人脸、眼、鼻、嘴和背景；非零瘦身产生可见且单调的躯干宽度收窄，同时保护头部、四肢和背景。
7. 前后对比、撤销/重做、归零、项目恢复、预览和原图导出保持三个非几何参数以及逐脸、逐身体目标几何参数的独立语义；一键自然美化本身作为一次可撤销操作。
8. 多主体、遮挡、低置信度或保护门失败时，对应塑形工具不可用，但非几何人像能力按脸独立判断，基础修图和导出始终不受阻。

### MVP 产品验证门

封闭测试进入下一阶段前，需要取得以下证据：

- 至少 80% 的目标测试用户在无口头指导下完成“导入到导出”。
- 至少 70% 的多图测试用户能正确区分整组调整与单张调整。
- 至少 60% 的测试用户认为三套推荐比从空白工具列表开始更省事。
- 固定样片盲评中，映见基础单张结果达到冻结后的最低自然度与保真评分。
- 固定人像盲评中，一键自然美化及其三个子能力、瘦脸、瘦身分别达到各自质量门；不得用综合结果或肤质得分替代任一子能力或几何塑形得分。
- 六项核心能力分别通过同图竞品门：相对原图的有效样片成对偏好率不低于 65%；与醒图执行同一任务相比，映见胜出或持平不少于 50%；自然度、身份保持和对应保护维度中位数不低于 4/5。
- 任一明显假面、身份变化、五官漂移、非皮肤误处理或背景变形均为灾难性失败，直接阻断对应能力，不用其他能力高分抵消。
- 关键图像正确性检查没有方向错误、明显二次压缩、预览/导出裁剪错位或原图覆盖。

这些阈值是首轮验证门，不是已经达到的业务指标。

### 真人交互决策

MVP_INTERACTION_DECISION_STATUS: pending
MVP_INTERACTION_WINNING_VARIANT: pending
MVP_INTERACTION_RETAINABLE_STRUCTURES: result_first_recommendations,explicit_group_current_scope,thumb_reachable_bottom_commands,immersive_photo_preview
MVP_INTERACTION_REJECTABLE_STRUCTURES: web_tool_dashboard,poster_style_mobile,hidden_scope_switching,scroll_bound_primary_commands

五名目标用户完成同一冻结 iOS 候选的无引导任务后，最终验收报告必须从上述冻结 ID 中结构化记录保留与拒绝的交互结构，并把前两行冻结为 `frozen` 与 `production`。当前 `pending` 是显式阻断状态；仅有总结文案、设计偏好或自动化通过不能代替真人交互决策。

## Scope

### P0.1 产品与质量基线

- 建立来源和使用权明确的固定样片集。
- 覆盖单人、多人、无人脸、不同肤色、逆光、夜景、混合光、风景、食物、宠物和低清晰度输入。
- 至少包含多组 2–6 张同场景但曝光、白平衡和主体位置不同的照片。
- 定义基础光色、肤色自然度、纹理保护、整组一致性、预览/导出一致性和失败降级的评分量表。
- 用同一批样片对醒图、Berry 和映见候选链路做真机对照。
- 冻结输入输出、色彩、元数据、设备和性能预算。

### P0.2 照片项目

- 支持导入 1–6 张照片；当前代码的 1–9 上限调整为 MVP 合同的 1–6。
- 导入后创建应用自有只读原图副本。
- 支持删除、调整顺序和重新选择重点照片。
- 自动保存项目状态，退出或应用重启后可以恢复。
- 单张损坏、不可读或不支持时隔离失败项，不让整个项目崩溃。
- 用户可删除项目及其应用内副本。

### P0.3 本地图像分析与三套推荐

- 在端侧得到方向、尺寸、清晰度、曝光、白平衡、人脸和主体等最小分析结果。
- 分析失败时回退到人工调校的通用安全配方，不阻塞编辑。
- 建立 12–18 套人工调校基础配方，按场景、安全范围和审美家族标记。
- 每次只展示一个主推荐和两个差异明确的备选。
- 三套方案至少覆盖“自然干净、氛围色彩、质感风格”三个可区分方向；具体名称可以根据输入变化，但不能只是同一效果的强弱版本。
- 方案卡提供结果预览、简短理由和适用提示。
- 三套预览全部由本地配方产生，不创建云端生成任务。
- 推荐只从声明过的参数和配方中选择，不执行任意脚本、着色器或自由参数。

### P0.4 单张基础编辑

- 提供曝光、高光、阴影、对比度、色温、色调、饱和度和清晰度/锐度等核心光色能力。
- 提供自由裁剪、常用比例裁剪、旋转、水平/垂直翻转、水平校正、克制的水平/垂直透视矫正和恢复原始构图。
- 提供至少 12 套结果可预览、强度可调、可归零的冻结滤镜；滤镜不是推荐方案的别名。
- 提供红、橙、黄、绿、青、蓝、紫、洋红八个通道的色相、饱和度与明度调整；首版不要求曲线。
- 提供画质改善结果入口，并展开为去噪、暗光提亮、去灰和细节锐化四个真实参数；四项均为 `0...100`，`0` 严格关闭，一键只写入可见参数且形成一次可撤销操作。
- 去噪必须降低细碎亮度/色彩噪声但不过度抹平边缘；暗光提亮优先恢复暗部可读性并保护高光；去灰提高低对比画面的层次但不得明显压黑或过饱和；细节锐化只做克制边缘增强，不制造明显白边、黑边或噪声放大。
- 四项效果必须由同一版本化本地管线执行，项目恢复、预览和原图导出保持相同参数语义；不适用或无法安全改善时允许保持原图，不阻断其他编辑或导出。

### P0.5 人像精修与基础塑形

- 有适用人脸时提供一键自然美化；它把安全推荐值写入质感磨皮、肤色与面部光线、瑕疵减弱三个真实参数，不形成隐藏处理层。
- 三个非几何子能力均可独立调整、归零和撤销；所有用户参数显示为 `0...100`，`0` 严格关闭。具体推荐值和最高安全值由固定样片校准后冻结，不在实现前拍脑袋写死。
- 质感磨皮、肤色与面部光线、瑕疵减弱支持最多三张高置信度人脸，按脸独立计算能力安全上限，但首版不为这三项非几何能力提供逐脸不同用户强度；应用不做年龄或性别推断。
- 瑕疵减弱是 P0，不再是可选增强；首版只做自动、高置信度、保守减弱，不提供手动画笔或点按修复。
- 最多三张高置信度人脸满足各自安全条件时，提供画面内逐脸选择和独立强度；每张目标脸提供瘦脸、小头、下颌、下巴、大眼、鼻形和嘴形的基础调整。默认值均为 0，不由三套推荐自动改变。
- 对明确选择的主体提供整体瘦身、增高、肩、腰和腿部的基础塑形；多人照片必须先选择目标，不以“只支持单人”或年龄推断替代目标选择。
- 所有几何塑形都必须使用人物/身体分割、关键点约束和背景保护；检测不到可靠目标时只关闭对应工具，不阻断其他编辑和导出。
- 妆容、发型、发色和发量不属于本轮 P0。
- 人像检测或引擎不可用时，稳定降级到基础光色与构图，不阻塞导出。
- 所有参数具有合法范围、默认值、归零、前后对比和撤销语义。
- 一次连续滑块手势只形成一个撤销步骤。

六项核心能力中的任一项若不能独立通过冻结样片和同图竞品门，只能进入内部开发候选，不得宣布“竞品入场能力已对齐”，也不得以其他能力替代。

### P0.6 简单局部与背景处理

- 提供人物主体抠图，至少覆盖单人、多人和常见发丝边缘；结果以可撤销蒙版保存，不改写原图。
- 提供背景虚化和纯色/用户图片替换；主体边缘、肤色和半透明区域不得产生明显黑白边。
- 提供基于画笔蒙版的基础消除和局部光色调整；首版允许传统修复，不要求生成式补全复杂结构。
- 局部工具必须提供画笔大小、擦除/恢复、蒙版可视化、撤销和重做；`0` 或空蒙版严格无效果。

### P0.7 整组一致性与单张覆盖

- 整组共享色彩倾向、对比关系、滤镜质感和全局强度。
- 每张照片拥有独立曝光、白平衡、肤色保护和安全强度补偿。
- 不得把全部绝对参数机械复制到每张照片。
- 用户可以从整组进入任意照片精修，并返回原来的组内位置。
- 单张修改默认只影响当前照片；需要同步整组的操作必须明确确认。
- UI 使用文字、结构和图标区分“整组”与“当前照片”，不能只依赖颜色。
- 用户可以恢复单张覆盖，而不破坏整组共享风格。
- 逐张检查时清楚标记未处理、已覆盖、失败和待导出状态。

### P0.8 原画质批量导出

- 从每张应用自有原图重新执行共享风格、逐张补偿和单张覆盖。
- 不从 Flutter 预览、屏幕截图或重复压缩的中间 JPEG 导出。
- 导出前显示张数、质量、格式、保存位置和预计处理状态。
- 显示逐张进度，允许取消尚未开始的项目。
- 单张失败不回滚已经成功的照片，并提供明确的失败项重试。
- 保持正确 EXIF 方向、长宽比和目标像素尺寸。
- 用户可在 JPEG 与 HEIF 中选择格式，在原尺寸、常用长边尺寸中选择输出尺寸，并选择有语义的高/标准/节省空间质量档；默认 JPEG、原尺寸、高质量、sRGB。
- Display P3 和完整元数据保留按基线决策决定是否启用，不得静默错误转换。
- 原图永不覆盖。
- 成功后可以调用系统分享，但不自动发布到外部平台。

### P0.9 信任、隐私和可访问性

- 首次本地出片不要求登录。
- 默认处理不上传照片。
- UI 明确说明三套方案是本地效果方向，不是三次 AI 生成。
- 不记录图片、路径、人脸特征、完整提示词或自由文本到普通日志。
- 匿名诊断保持用户主动开启，关闭后立即停止供应商采集。
- 加载、空态、部分失败、完全失败、取消和恢复都有用户可理解的状态。
- 关键控件有语义标签、足够触控区域，并支持动态文字和屏幕阅读器。
- 前后对比、整组/单张状态和错误不能只依赖颜色表达。

## Experience Requirements

### 首页与项目入口

- 主动作是“开始修图”，不以工具分类或 AI 功能宫格作为首屏。
- 存在未完成项目时，首页同时提供“继续上次编辑”，并显示照片数量和最后编辑时间。
- 首次使用不展示账号、订阅或云端授权阻断。

### 照片选择

- 支持单张和多张从同一个入口开始。
- 选择数量、支持格式和不可用照片在确认导入前可理解。
- 超过六张时不静默截断，应说明上限并允许用户调整选择。
- 导入失败按照片呈现，成功项可以继续。

### 分析与三方案

- 分析等待页展示确定性进度或阶段，不使用无法结束的装饰性等待。
- 用户离开或应用进入后台后，项目保持可恢复。
- 推荐页以当前照片或代表照片展示三个方向，并可快速检查组内其他照片。
- 主推荐具有明确层级，但三个方向都可以直接选择。
- 每个方向显示名称、简短理由和本地处理说明。
- 方案尚未准备好、部分预览失败和全部分析失败分别有明确回退。

### 编辑工作台

- 多图项目默认进入“整组”范围；单图项目不显示无意义的整组切换。
- 顶部或主预览区域持续显示当前照片及其组内位置。
- 整组/当前照片范围是工作台一级状态，并在参数修改前后保持可见。
- 默认先展示系统建议调整和常用参数，完整 MVP 工具渐进展开。
- 前后对比、撤销、重做和重置不隐藏在二级设置中。
- 人像首层固定为一键自然美化、瘦脸、瘦身；进入一键自然美化后展开质感磨皮、肤色与面部光线、瑕疵减弱。只有在各自能力可用且检测到适用对象时出现，失败不会留下不可操作入口。
- 从当前照片返回整组时保留滚动位置、选中照片和未导出状态。

### 导出确认与结果

- 导出确认页逐张显示将要导出的照片以及失败或不可用项。
- 开始前说明张数、格式、画质和保存位置，不在此时新增未提前说明的付费限制。
- 进行中显示总体和逐张进度，并允许取消剩余工作。
- 完成页分别报告成功、失败和取消数量，失败项可重试。
- 系统分享是导出后的可选动作，不替代保存成功证据。

### 项目状态模型

```text
empty
  → importing
  → analyzing
  → choosingRecommendation
  → editing
  → exporting
  → exported
```

- `importing`、`analyzing` 和 `exporting` 可以产生可恢复的部分失败。
- 返回编辑不会丢失已选择方案、共享风格或单张覆盖。
- 应用重启后恢复到最后一个安全持久化状态，不自动重放未确认的导出。
- 任一供应商或设备能力失败都映射为产品状态，不暴露原始实现异常。

## User Stories

1. 作为新用户，我希望无需注册即可开始修图，以便先判断产品是否适合我。
2. 作为重视隐私的用户，我希望默认编辑完全留在设备本地，以免照片在不知情时上传。
3. 作为只有一张重点照片的用户，我希望可以单张导入，以便映见不只服务组图场景。
4. 作为准备发布组图的用户，我希望一次导入最多六张照片，以便在一个项目中完成整组处理。
5. 作为用户，我希望损坏或不支持的文件被单独标记，以免一张坏图破坏整个项目。
6. 作为回访用户，我希望未完成项目可以恢复，以免中断导致编辑丢失。
7. 作为用户，我希望应用自动分析照片，以免自己判断曝光和色彩问题。
8. 作为用户，我希望分析失败时仍有可靠回退方案，以便继续编辑。
9. 作为不了解滤镜名称的用户，我希望看到三个明显不同的结果，以便直接按效果选择。
10. 作为用户，我希望看到一个主推荐和两个备选，以便应用帮助决策但不剥夺选择。
11. 作为用户，我希望每个推荐有简短理由，以便理解应用准备改善什么。
12. 作为关注成本的用户，我希望三个默认预览都在本地产生，以免浏览方案消耗云端权益。
13. 作为用户，我希望推荐避开人脸和复杂光线的危险强度，以便自动结果保持自然。
14. 作为用户，我希望调整选中方案的整体强度，以便快速变淡或增强效果。
15. 作为组图用户，我希望照片共享同一视觉方向，以便发布时看起来属于同一组。
16. 作为输入光线不同的用户，我希望每张照片得到独立补偿，以免统一风格造成欠曝或偏色。
17. 作为用户，我希望逐张检查整组照片，以免自动处理隐藏坏结果。
18. 作为用户，我希望随时知道正在编辑整组还是当前照片，以免误改全部照片。
19. 作为用户，我希望单张修改默认只留在当前照片，以便重点精修保持安全。
20. 作为用户，我希望同步整组前有明确动作，以便大范围修改一定是有意操作。
21. 作为用户，我希望从单张精修返回原来的组内位置，以便工作流保持连续。
22. 作为用户，我希望可以将某张照片恢复到整组风格，以便放弃失败的单张覆盖而不必重来。
23. 作为用户，我希望调整核心光色参数，以便修正一个大体正确的推荐。
24. 作为用户，我希望使用裁剪、旋转和水平校正，以免基本构图问题还需要切换应用。
25. 作为人像用户，我希望一键自然美化直接给出可信的第一结果，以免先理解多个专业参数。
26. 作为希望继续精调的用户，我希望一键结果展开为真实的磨皮、肤色光线和瑕疵参数，以便理解并修改实际发生的处理。
27. 作为人像用户，我希望独立控制质感磨皮并保留皮肤纹理，以免综合强度只能在“没效果”和“塑料感”之间选择。
28. 作为人像用户，我希望独立调整肤色与面部光线，以便改善暗沉和色偏但仍保持本人肤色。
29. 作为存在痘印或色斑的用户，我希望应用自动、保守地减弱明显瑕疵，以免必须切换其他修图应用。
30. 作为有痣、雀斑、皱纹、妆容或胡须的用户，我希望无法确定的细节被保留，以免美化改变身份特征。
31. 作为多人照片用户，我希望最多三张清晰成人脸分别获得安全的非几何改善，以免整张照片因存在多人而完全关闭人像能力。
32. 作为人像用户，我希望可以显式、克制地瘦脸，并保护五官和背景不变形。
33. 作为全身照用户，我希望可以显式、克制地调整躯干宽度，并保护头部、四肢和背景。
34. 作为使用不支持设备或困难输入的用户，我希望每项人像能力独立稳定降级，以便基础编辑和导出仍然可用。
35. 作为用户，我希望每项调整都能归零，以便安全尝试。
36. 作为用户，我希望一次连续滑动或一次一键美化只形成一个撤销步骤，以便撤销符合操作意图。
37. 作为用户，我希望查看前后对比，以便判断修改是否真的改善照片。
38. 作为用户，我希望原图始终不被修改，以免使用应用损坏源文件。
39. 作为用户，我希望导出从原始像素生成，以免得到截图级预览画质。
40. 作为用户，我希望导出前看到张数、质量和保存位置，以便结果可预期。
41. 作为批量导出用户，我希望看到逐张进度，以便理解长任务状态。
42. 作为用户，我希望某张失败时保留其他成功结果，以免重复已完成工作。
43. 作为用户，我希望失败项被明确标记并可重试，以便只处理真正的问题。
44. 作为用户，我希望取消尚未执行的导出，以便控制等待、耗电和发热。
45. 作为用户，我希望导出的方向、尺寸和色彩正确，以便成片符合批准的预览。
46. 作为用户，我希望导出后使用系统分享，以免应用要求访问社交账号。
47. 作为无障碍用户，我希望控件和编辑范围被清楚朗读，以便借助辅助技术完成流程。
48. 作为产品测试人员，我希望默认路径能证明没有创建云端图片任务，以便核心成本合同可执行。
49. 作为产品团队成员，我希望每项能力的竞品质量门分别报告，以免工程完成或综合高分被误认为能力已对齐。

## Implementation Decisions

### Product flow

- The product has one primary creation flow: import, local analysis, three recommendations, group/single editing, review and batch export.
- Single-photo and multi-photo projects use the same model; a single-photo project is not a separate editor architecture.
- Recommendation is the default entry into editing. The complete tool list is progressively disclosed.
- The MVP supports 1–6 photos. This supersedes the current implementation limit of 1–9 for product behavior.
- Natural-language intent is not required for first export and is excluded from the MVP.

### Editing state

- The original input is immutable.
- A project stores shared style, per-photo adaptive compensation and per-photo user overrides as separate layers.
- The effective recipe is computed from those layers and remains serializable, versioned and reversible.
- Undo and redo store semantic operations rather than full-resolution bitmaps.
- A project save is committed before new state is published to the UI.
- Editing scope is explicit: group operations and current-photo operations cannot be inferred only from the current screen.

### Rendering boundary

- Flutter owns UI, product state and task orchestration; it does not perform high-resolution per-pixel processing.
- The native rendering capability owns preview resources, deterministic processing and final export.
- Flutter and native layers exchange file references, declared parameters, progress and stable errors; slider interaction does not transfer complete image bytes.
- Export replays the effective recipe from the original input.
- The first production vertical slice must prove one shared parameter from Flutter interaction through iOS native preview to original-resolution export. Android remains a deferred adapter, not a launch gate.
- Platform-specific or commercial portrait capabilities remain behind a supplier-neutral portrait boundary.

### Recommendation system

- The initial catalog contains 12–18 manually tuned recipes rather than an unbounded preset library.
- Analysis and recommendation are deterministic and on-device.
- A recommendation can only select declared recipe families, parameters and safe ranges.
- The three directions must differ in intent, not merely intensity.
- If analysis or portrait detection fails, a safe general catalog remains available.
- Personal ranking and model training are not required for the MVP.

### Portrait quality

- Natural portrait quality is a release gate, not a checkbox based on API availability.
- The MVP core package is one-tap natural beautification, independently controllable texture-preserving smoothing, skin tone and face lighting, conservative automatic blemish reduction, explicit face slimming and explicit torso slimming.
- One-tap natural beautification is a semantic command that writes the three non-geometric child parameters. It is not persisted or rendered as an additional hidden effect.
- The project persists three photo-level non-geometric parameters plus independent geometry targets: each face stores face slimming, head size, jaw, chin, eyes, nose and mouth; each body stores overall slimming, height, shoulders, waist and legs. It also persists declared analysis/effect versions and selected target indices. Unsigned parameters use `0...100`; bidirectional parameters use `-100...100`; `0` strictly disables that effect.
- Non-geometric processing supports up to three high-confidence faces with per-face safety caps and one photo-level user strength per parameter. Geometry supports deterministic per-target selection and independent values for up to three eligible faces and three eligible bodies; the app does not infer age or sex.
- Face/body geometry defaults to zero, remains outside automatic recommendations, and is exposed only when landmark, segmentation and background-safety gates pass.
- Freehand liquify, posture generation, muscle/chest/hip reshaping, beautification presets and makeup are excluded. The bounded landmark- and mask-constrained face/body controls listed in P0.5 remain in scope.
- Apple system capabilities, self-built processing and license-compatible open on-device models are evaluated first. A commercial candidate is only a fallback when the same fixed corpus proves that these candidates cannot reach the frozen quality floor.
- Failure or license unavailability degrades to base editing and never prevents project access or export.
- Natural skin/light/texture quality is governed by [Natural Portrait Retouch Vertical Slice Spec](natural-portrait-retouch-vertical-slice-spec.md); face/body geometry, applicability and protection gates are governed separately by [Portrait Reshape Vertical Slice Spec](portrait-reshape-vertical-slice-spec.md). Each capability must freeze its own candidate before product integration.
- When goals conflict, the order is identity and facial-feature preservation, non-skin/background protection, real skin texture, visible natural improvement, then support for more difficult inputs.

### Export and failure behavior

- Batch export uses bounded concurrency to avoid unbounded memory growth.
- Each photo has an independent terminal state.
- Cancel stops work that has not reached an irreversible platform save operation; already saved outputs remain valid.
- Product errors use stable categories such as unsupported input, analysis unavailable, preview unavailable, export failed and storage denied.
- Provider, framework and raw platform error strings are not exposed as product contracts or analytics payloads.

### Privacy and cost

- The default MVP path is fully local and creates zero cloud image tasks.
- Cloud semantic editing, entitlements and server budget infrastructure are excluded from this MVP.
- Existing privacy-safe analytics may measure a finite allowlisted funnel only when anonymous diagnostics is enabled.
- Photos, paths, face features, free text and raw errors are prohibited telemetry fields.

## Testing Decisions

### Highest behavior seam

The main acceptance seam is one observable journey:

> Import one or multiple photos → receive three local recommendations → select one → edit the group and one photo → export from the originals.

This seam must also assert that the default journey creates no cloud image task. Tests observe user-visible behavior, saved project state, declared engine requests and exported results; they do not bind to individual widgets, shaders, native classes or SDK objects.

The production home-to-editor path is additionally exercised by `integration_test/ios_mvp_journey_test.dart` through `scripts/test_ios_mvp_integration.sh` on an iOS Simulator. It proves the Flutter runtime navigation and core interaction contract with deterministic system-boundary fakes; it does not satisfy physical-device image-quality, performance, PhotoKit or sharing gates.

### Product-state tests

- Import limit, invalid-input isolation and project deletion.
- Shared style, adaptive compensation and single-photo override merge rules.
- Group/current scope switching and explicit synchronization.
- Gesture-level undo/redo, reset and before/after state.
- Project persistence, restart recovery and recipe-version migration.
- Analysis failure and portrait capability fallback.
- Per-photo export state, cancellation, partial success and retry.

Existing editor session, photo project session, importer, store and method-channel exporter tests are prior art and should be extended at their public interfaces.

### Image-quality tests

- Use licensed fixed samples with a manifest and hashes.
- Automatically verify orientation, dimensions, crop coordinates, deterministic output, preview/export trend and unacceptable compression regressions.
- Use numeric or perceptual tolerances for deterministic light/color operations.
- Treat the frozen cross-platform `neutral-export-v1` and `exposure-semantic-v1` reports as retained engineering evidence, not as current iOS MVP gates.
- On iOS, every non-neutral adjustment requires a parameter-specific direction, visible-strength and clipping contract over the frozen corpus plus blinded review; contrast, warmth, selective tone, saturation, tint, and clarity contracts are frozen, and neutral pixel tolerance is not evidence of retouch quality.
- Use blinded human review in addition to automation for skin naturalness, texture preservation, recommendation quality and group coherence.
- Compare candidate engines using identical inputs, parameter levels, devices and scoring rubrics.
- Before production integration, run two isolated effect Spikes: multi-face skin/feature/background protection for up to three faces, and blemish-versus-identity-detail discrimination plus local repair. Compare system, self-built and license-compatible open candidates at the same observable seam.
- For every one of the six core abilities, compare the same input and task anonymously against the frozen direct competitor path. Require at least 65% paired preference over the original on improvable samples and at least 50% win-or-tie against the competitor; report every ability and protected subset separately.
- Do not claim quality parity based only on screenshots or one favorable sample.

### Native and performance tests

- Verify Flutter-to-native parameter contracts and stable error mapping.
- Verify preview resource creation, update, release and foreground/background recovery.
- Verify the frozen `ios-preview-export-semantic-v1` CVPixelBuffer/final-JPEG contract, and verify final export runs away from the Flutter UI thread.
- Verify bounded batch concurrency and low-memory fallback.
- Run Profile or Release on frozen low-, mid- and high-tier physical iOS devices.
- Record first preview time, slider response, preview frame rate, per-photo export time, peak memory and thermal behavior.
- Debug and simulator results are development evidence only.

### Usability tests

Target users complete the primary journey without coaching. Observe whether they:

- understand that three recommendations are local effects, not three generated images;
- can distinguish group edits from current-photo edits;
- can find and complete focused single-photo refinement;
- can compare, reset and undo changes;
- understand export quality, destination, progress and partial failure;
- feel that the recommended start reduces work compared with a blank tool list.

## Acceptance Criteria

### Product closure

- A new user completes first export without an account.
- Both one-photo and 2–6-photo projects complete the same primary flow.
- Three useful schemes are available even when analysis fails.
- Group style, adaptive compensation and current-photo overrides remain distinguishable and reversible.
- A user can refine a key photo and return to group review without losing position or state.
- Batch export reports per-photo progress, partial failure and retry.

### Image closure

- Preview and export apply the same declared recipe semantics.
- Export uses the original input and never overwrites it.
- Fixed samples pass orientation, dimensions, crop, color and compression checks.
- Quality improvement keeps zero values pixel-equivalent, preserves preview/export semantics, and passes frozen noise, low-light, haze and edge-protection fixtures.
- One-tap natural beautification expands to the exact three saved non-geometric parameters and produces no hidden residual effect when they are all zero.
- Texture smoothing, skin-light correction and blemish reduction each meet their frozen quality and protection thresholds, including the multi-face and identity-detail subsets.
- Every one of the six core portrait abilities independently passes the same-image competitor gate; aggregate scores cannot compensate for a failed ability.
- The frozen group-coherence review thresholds are met.
- Applicable single-person samples prove visible, bounded face slimming and torso slimming independently; feature, limb and background protection gates pass.
- Reopening and exporting a project does not accumulate repeated compression.

### Runtime closure

- The Flutter UI remains responsive during preview and export.
- Profile/Release physical-device evidence meets the frozen latency, frame-rate, memory and thermal budgets.
- Backgrounding, cancellation, low memory and unsupported capabilities have stable recovery or fallback.
- No unsafe debug-only framework member is evaluated on Profile or Release production paths.

### Privacy and cost closure

- Default editing and all three recommendations work offline after installation.
- The primary journey uploads no photo and creates no cloud image task.
- Telemetry remains disabled until explicit consent and accepts only allowlisted fields.
- Deleting a project removes its app-owned working copies according to the documented retention contract.

## Out of Scope

- Cloud erase, generative fill, expansion and background replacement.
- AI portraits, face swap, outfit replacement and virtual characters.
- Natural-language editing and free-form prompt input.
- Personalized model training or recipe ranking.
- Accounts, subscriptions, credit packs and production monetization.
- Real-time camera, Live Photo, video, audio and live-stream beautification.
- Text, fonts, stickers, templates, collages and creator marketplaces.
- Manual brushes, complex local masks, layers, curves, channels and RAW workflows.
- Super-resolution, generative detail reconstruction, model-based face restoration and severe motion-deblur recovery; bounded local denoise, low-light recovery, dehaze and detail sharpening remain in scope.
- Freehand or generative facial/body reshaping, posture generation, muscle/chest/hip editing and makeup; the bounded landmark- and mask-constrained controls defined by the portrait-reshape vertical slice remain in scope.
- Teeth or eye-white brightening, dedicated eye-bag/nasolabial removal, child-specific portrait effects, and manual blemish/healing brushes.
- Automatic social publishing, community and content feeds.
- Store submission, test distribution and public release.

## Further Notes

图像格式、样片配额、评分量表、设备矩阵和性能预算以《MVP 图像质量与工程基线》及其图像输入输出 ADR 为规范性门禁。若本 Spec 与质量基线冲突，必须先显式修改两份文档并记录原因，不能由实现代码暗中选择。

人像几何的参数、适用性、背景保护和验收门以《[人像塑形纵切 Spec](portrait-reshape-vertical-slice-spec.md)》为规范来源；自然肤质仍以《[自然人像精修纵切 Spec](natural-portrait-retouch-vertical-slice-spec.md)》为准。

### Required execution order

1. Freeze the quality corpus, supported image contract, device matrix and measurable budgets.
2. Build a throwaway interaction prototype for the complete single/group journey and test comprehension.
3. Prove the Flutter-to-native preview/export vertical slice on iOS; retain the Android adapter as deferred, non-blocking work.
4. Prove the multi-face non-geometric protection Spike and the conservative blemish-reduction Spike before changing production portrait UI or recipes.
5. Freeze texture smoothing, skin-light correction and blemish reduction as three independently controllable effects, then define one-tap natural beautification as a semantic recipe operation over them.
6. Prove the bounded face and body geometry controls separately, including target selection, landmark/pose/segmentation applicability and background-protection gates; the face-slim and overall-body-slim headline abilities retain their separate competitor gates.
7. Run the six same-image competitor gates and freeze only candidates that meet their own result contract.
8. Implement the single-photo base editor on the proven rendering path.
9. Add deterministic analysis and three local recommendations.
10. Add shared style, per-photo compensation and single-photo overrides.
11. Complete bounded batch export, recovery and quality verification.
12. Run uncoached usability testing and physical-device Profile/Release gates.

Interaction prototype and rendering Spike may proceed in parallel after the baseline is frozen. Production feature expansion must not outrun failed image-quality or architecture gates.

### Stop conditions

Pause product implementation and revisit the corresponding decision if:

- the native vertical slice cannot meet the frozen interaction or memory budget;
- preview and original-resolution export cannot maintain the same recipe semantics;
- no portrait candidate reaches the naturalness floor within acceptable license and privacy constraints;
- multi-face protection cannot independently close low-confidence faces, or blemish reduction cannot distinguish temporary blemishes from identity details at a useful strength;
- any of the six core portrait abilities fails its own same-image competitor gate; another ability's score cannot waive this stop condition;
- any P0 face or body geometry control cannot meet its frozen feature/body/background protection gate at a visibly useful strength;
- users repeatedly mistake group and single-photo scope;
- three recommendations do not reduce decision effort in uncoached testing;
- group adaptation performs no better than applying one absolute preset to every photo.

### Relationship to existing work

Current import, project persistence, three base parameters, undo and single-photo export are reusable foundations only where they satisfy this specification. Existing behavior is not grandfathered into the MVP if it conflicts with the 1–6 project limit, the layered recipe model, the native preview contract or the image-quality gates.
