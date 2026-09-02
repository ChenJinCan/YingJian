---
name: Yingjian MVP
colors:
  surface: '#121415'
  surface-dim: '#121415'
  surface-bright: '#38393a'
  surface-container-lowest: '#0c0e0f'
  surface-container-low: '#1a1c1d'
  surface-container: '#1e2021'
  surface-container-high: '#282a2b'
  surface-container-highest: '#333536'
  on-surface: '#e2e2e3'
  on-surface-variant: '#d1c5af'
  inverse-surface: '#e2e2e3'
  inverse-on-surface: '#2f3132'
  outline: '#9a907c'
  outline-variant: '#4d4635'
  surface-tint: '#ecc14a'
  primary: '#ffd975'
  on-primary: '#3e2e00'
  primary-container: '#e6bc45'
  on-primary-container: '#624c00'
  inverse-primary: '#755b00'
  secondary: '#c9c6bf'
  on-secondary: '#31302b'
  secondary-container: '#484741'
  on-secondary-container: '#b8b5ae'
  tertiary: '#e1dcd4'
  on-tertiary: '#32302b'
  tertiary-container: '#c5c0b9'
  on-tertiary-container: '#514e49'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#ffdf91'
  primary-fixed-dim: '#ecc14a'
  on-primary-fixed: '#241a00'
  on-primary-fixed-variant: '#594400'
  secondary-fixed: '#e6e2da'
  secondary-fixed-dim: '#c9c6bf'
  on-secondary-fixed: '#1c1c17'
  on-secondary-fixed-variant: '#484741'
  tertiary-fixed: '#e7e2da'
  tertiary-fixed-dim: '#cac6be'
  on-tertiary-fixed: '#1d1b17'
  on-tertiary-fixed-variant: '#494741'
  background: '#121415'
  on-background: '#e2e2e3'
  surface-variant: '#333536'
typography:
  display-lg:
    fontFamily: SF Pro Display
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  display-md:
    fontFamily: SF Pro Display
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: SF Pro Text
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: SF Pro Text
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-lg:
    fontFamily: SF Pro Text
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: SF Pro Text
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  display-lg-mobile:
    fontFamily: SF Pro Display
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  photo-height-mobile: 65vh
  photo-height-desktop: 72vh
  margin-main: 20px
  gutter-ui: 12px
  stack-gap: 8px
  floating-dock-bottom: 32px
---

## Visual Direction

> 状态：iOS 交互方向已由本地可点击原型验证。旧 V1 流程图和界面方向图不再代表当前信息架构；它们不得作为实现依据。

### 界面视觉语言

“原生静谧画廊”：照片与结果是内容层；系统导航、控制与 Sheet 是功能层。高端感来自准确层级、系统字体、克制材质、稳定图片几何和及时反馈，不来自海报墙、装饰字体、厚重阴影或到处铺玻璃。

### 结果风格 V1

同一源照片、同一构图下固定展示四个用户能立即理解的方向：**日系、胶片、插画、电影感**。它们以效果命名，不暴露“官方 / 文字 / 语音 / 参考图 / AI 重绘”等执行来源。日系、胶片和电影感保持人物身份与结构；插画按云端内容变化合同执行。

## Interactive Mobile Prototype

本地可点击原型位于 `.scratch/prototypes/style-first-mobile/`。它验证的不是传统编辑器，也不是在定风格后再让用户选择结果类型，而是首页先按任务分流的四条独立路径：

```text
首页
├─ 优化照片 → 选图片 → 点「自然优化 / AI 修复 / 高清放大 / 老照片修复」→ 静态结果
├─ 换风格 → 选图片 → 点「日系 / 胶片 / 插画 / 电影感」→ 静态结果
├─ 去背景 / 去杂物 → 选图片 → 点「人物白底 / 透明抠图 / 替换背景 / 去路人 / 涂抹去物」→ 静态结果
└─ 做动态效果 → 选图片 → 点「轻微动态 / 镜头推进 / 光影流动 / AI 自然动效」→ 动态结果
```

- 首页显示品牌与四个整块可点击的 iOS destination tiles：**优化照片**、**换风格**、**去背景 / 去杂物**、**做动态效果**。每个 tile 左侧是任务与一句结果说明，右侧是语义预览；不得使用重复满幅人像的海报墙。
- 点击入口即确定任务；正式产品随后调用系统选图，原型中直接用样片模拟选图完成。
- `CreationTask=optimize|style|cleanup|motion` 是入口身份；任务内还必须保存用户明确选择的 `CreationCapability`。`CreationIntent=apply|motion` 只区分静态页面和动态页面。旧 `apply` 草稿恢复为 `style`。
- 进入工作区时不预选任何能力；能力按固定产品顺序完整展示，不依据照片、分析、历史、设备或 AI 推荐、排序、突出、组合或替用户切换。
- 能力按钮本身就是本地执行动作；点击后留在同一工作区并直接把结果显示在图片上，不再切换到说明页或要求第二次点击“应用”。未跑通完整闭环的能力显示明确不可用，不能自动降级到其他能力。
- 换风格只展示四个结果导向选项：**日系、胶片、插画、电影感**。用户点击本地风格即应用；插画需要云端生成时直接进入必要的确认 Sheet，不暴露提示词、模型或输入方式。
- 云端生成确认使用底部 Sheet，明确上传范围与权益；确认后任务状态悬浮在图片上，能力栏仍可操作。第一方网关未启用时不得上传、创建任务或收费。本地能力不显示云端确认。
- 静态结果使用媒体查看器；服务接入后的动态结果默认暂停并由用户明确播放。保存是主操作，分享走系统分享，返回当前任务不隐式切换任务。

运行方式及验证边界见 `.scratch/prototypes/style-first-mobile/README.md`。该原型是本地验证材料，不是 Flutter 实现或发布证据。

## Product Mental Model

The production experience starts from four explicit user tasks:

```text
优化照片：选图片 → 用户选一种优化能力 → 执行
换风格：  选图片 → 用户点一种结果风格 → 直接看到应用或生成结果
去背景 / 去杂物：选图片 → 用户选一种清理能力 → 执行
做动态效果：选图片 → 用户点一种动态效果 → 直接生成对应动态结果
```

This is not a simplified editor. It is a task-first, style-led creation experience.

- **优化照片**, **换风格**, **去背景 / 去杂物**, and **做动态效果** are four stable top-level destinations, chosen before photo selection.
- **选图片** starts one creation from one read-only source photo within the chosen task.
- After photo selection, the user explicitly selects one named `CreationCapability`; entering a task never preselects or authorizes a capability.
- The style task speaks only in visible outcomes: **日系、胶片、插画、电影感**. Internal style definitions and execution providers never become a second user decision.
- `CreationTask` is user identity; `CreationIntent` only separates static and dynamic pages. The selected capability decides local, cloud, static-generation, or motion-generation execution, and cloud work still requires a separate confirmation.
- Current availability remains honest: local choices execute immediately; cloud choices open only their required consent and then create one bounded task. A failed or unavailable cloud task never blocks another choice.
- Dynamic generation uses the source photo and user-selected motion effect directly. It never requires a static apply or export first.

Do not expose a generic editor shell, all-purpose tool categories, parameter sliders, a “自己调” escape route, or any recommendation surface. Optimize and cleanup expose only the confirmed, task-specific named capabilities. Parameters may exist behind the interface only as validated execution details of the capability the user selected.

## Experience Principles

1. **The image is the interface.** The source, preview, or result owns most of the screen and never moves merely because a transient control opens.
2. **One decision at a time.** Choose the task, then explicitly choose one capability. No capability is selected by default.
3. **Style is the user language.** Names, visual examples, plain-language descriptions, and references describe a desired result; tool names do not.
4. **AI obeys instead of deciding.** Tapping a named choice is its primary action. AI may execute that exact choice after any required privacy/cost confirmation; it never selects, recommends, ranks, combines, or substitutes on the user's behalf.
5. **State is honest.** Preview, applied result, generation task, and exported media are visually and verbally distinct.
6. **Calm beats density.** Fewer surfaces, low visual noise, short labels, and generous space matter more than exposing every capability.

## iOS Interaction Baseline

- Use a single `NavigationStack`: Home is the root, and each task owns one workspace route. Confirmation, progress, and result are phases inside that workspace rather than a stack of synthetic pages.
- Production photo selection uses system `PhotosPicker`, single image only. `CreationTask` is fixed before the picker appears; `CreationIntent` is derived from it; cancel returns to Home without creating an empty draft.
- Back and the short task title float over the image stage inside the safe area; there is no dedicated full-width navigation bar. Preserve system back behavior, semantic colors and system text styles. UI text uses SF Pro with PingFang SC fallback; decorative serif type is limited to a supplied brand asset, never navigation, buttons, states, or style names.
- Liquid Glass belongs only to the functional layer: navigation controls, one continuous bottom control group, and temporary Sheet surfaces. Photos, task tiles, style thumbnails, and other content surfaces never become Glass.
- Standard controls are at least 44 × 44 pt; prominent actions are at least 52 pt high. Every custom control has a visible press state and an accessibility label.
- The interface adapts to Dynamic Type, Bold Text, Increase Contrast, Reduce Transparency, and Reduce Motion. At accessibility sizes, content scrolls or control regions grow; labels are not shrunk or clipped.
- Browser prototypes approximate iOS geometry only. System picker, native share UI, real video playback, haptics, interactive edge-back, material rendering, and final safe-area behavior require Simulator and physical-device validation.

Platform guidance: [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Information Architecture

### Home

- Show exactly four destination tiles in one full-width vertical stack: **优化照片** — “调亮、清晰、增强质感”；**换风格** — “日系、胶片、插画、电影感”；**去背景 / 去杂物** — “抠图、白底、清理路人杂物”；**做动态效果** — “让静态照片自然动起来”。每张整卡均为点击目标；手机首页不得把四个任务排成 2 × 2 宫格，也不得把入口藏到加号、标签栏或菜单中。
- Tiles use the standard content layer, continuous 24–28 pt corners, concise secondary copy, and a small semantic preview. At accessibility sizes each tile may grow and the page scrolls while preserving the single column; tiles are not full-bleed posters and do not use Glass.
- Selecting a destination fixes `CreationTask=optimize|style|cleanup|motion`, from which `creationIntent=apply|motion` is derived, before the system photo picker opens.
- Returning from the picker without a photo stays on Home. Selecting a photo creates a draft in the chosen branch; it never silently replaces or deletes another draft.
- If drafts are restored, each resume surface retains its original `CreationTask` identity. Historic `apply` drafts migrate to `style`; a draft cannot reopen as optimize or cleanup by inference.
- Settings remains secondary. Do not add a tab bar, creation templates, camera placeholders, community content, or promotional modules to the main path.

### Task Workspace

Each task owns its workspace state. The static/creation branches may share layout components, but never share one visible decision surface. Each workspace has three layers:

1. **Floating navigation:** a 44 pt Back target and compact task-title material float above the media instead of reserving a navigation-bar row.
2. **Image stage:** the complete source, style preview, static result, or dynamic result on a stable media canvas.
3. **Bottom control layer:** only the current task's named, direct-action choices plus compact save/share actions for a completed result.

Keep the image stage stable across all states. Text, voice, reference selection, consent, and failures use system-style sheets or inline status that preserve the image context.

### Capability Choice

- Optimize shows **自然优化 / AI 修复 / 高清放大 / 老照片修复**.
- Style shows **日系 / 胶片 / 插画 / 电影感**.
- Cleanup shows **人物白底 / 透明抠图 / 替换背景 / 去路人 / 涂抹去物**.
- Motion shows **轻微动态 / 镜头推进 / 光影流动 / AI 自然动效**.
- Every list is single-select, initially empty, and displayed in fixed product order. No option is recommended, highlighted, reordered, combined, or substituted based on the image, analysis, history, device, or AI.
- A tap executes the exact local choice immediately. A cloud choice opens its required privacy/cost confirmation directly; there is no intermediate description or generic “应用” screen. Failure preserves the current image and selection, with no recommendation, fallback, or automatic switch.

### Result State

- A static result uses a media viewer with primary **保存到照片**, system **分享**, and a task-appropriate secondary action.
- A dynamic result, after the service is connected, uses native video playback semantics with primary **保存视频**, system **分享**, and secondary **换效果**. It does not autoplay.
- Back exits the current task workspace to Home. It stays reachable as a floating 44 pt control in source, processing and result states.
- While a dynamic result is playing, the central pause control fades after about 1.5 seconds and returns when the user taps the media. Paused state keeps the play control visible.
- Result actions stay on the same visual surface; do not introduce an export editor or a long-lived results tab.
- The task choices remain visible with the result, so changing the current effect requires no “重新选择” transition. A new tap replaces only the current projected result and never overwrites the source.
- Switching among optimize, style, cleanup and motion is not a result action; the user returns to Home and deliberately enters the other task.

## Core Components

### Photo Stage

- Occupies roughly 60–72% of available height when controls are collapsed.
- Uses the source aspect ratio and `contain` behavior so the complete preview remains visible; restrained 20–24 pt continuous corners may frame the media canvas.
- Only essential status may overlay the photo: loading, unavailable preview, generation progress, or playback state.
- Original comparison is momentary and read-only. It is not an editing mode.

### Style Strip

- The style workspace always shows exactly **日系、胶片、插画、电影感** in one direct-action rail. Motion uses its own effect choices; optimize and cleanup do not expose a style rail merely to make their entry surfaces look alike.
- A horizontally scrollable Photos/Filters-style rail of 52–56 pt rounded previews with visible names.
- Each option has at least a 44 pt hit region and an unmistakable selected state using accent stroke plus checkmark/semantics, never color alone.
- No style is selected by default. Selecting a local card applies it and displays the newest result in place. Selecting 插画 opens its required cloud confirmation; merely entering the page never uploads, generates, or charges. Older responses cannot replace the latest selection.
- Do not group styles by editing tools. Optional curation uses human concepts such as mood, occasion, or visual character.

### Direct Choice Action

The named option is the action. Do not render a second full-width “应用自然优化 / 应用风格 / 生成动态照片” button or replace the control area with an explanation card:

- local optimize, style, cleanup and motion choices execute on tap;
- choices that need a source resource, such as 替换背景, open that system picker on tap and continue after the resource is chosen;
- cloud choices open the minimal consent Sheet on tap and create exactly one task only after confirmation;
- save/share appear compactly only when a usable result exists.

Never render actions for two tasks on the same screen. The capabilities may share source and static safety contracts internally, but the interface preserves the task the user chose on Home.

### Generation Status

- Any selected cloud or generative capability first shows what will be uploaded, expected output, waiting time, cost or quota, and cancellation boundary. Selecting the capability itself never creates a task.
- Current state: the motion service is unavailable. Show one clear unavailable state and do not upload, create a task, charge quota, or fake progress.
- After the service is connected, state what will be uploaded, expected output, waiting time, cost or quota, and cancellation boundary before creating a task.
- After confirmation, keep one honest, compact status over the image while retaining the bottom choices. Status text, reconciliation and progress must never occupy a blocking bottom panel or disable unrelated choices. Do not fake percentages or create a second task when local waiting times out.

## Visual Language

### Color

- Production uses Apple semantic colors and dynamic Color Sets for Light, Dark, Increase Contrast, and Reduce Transparency. Front-matter hex values are dark-appearance prototype fallbacks only.
- Use a black media canvas and restrained system content surfaces. The photo supplies most of the color.
- Reserve `primary` and `primary-container` for the current selection, primary confirmation, progress focus, and success—not decoration.
- Use tonal surfaces and thin `outline-variant` borders instead of heavy shadows or large glass effects.
- Error color appears only with a concise explanation and a recovery action.

### Typography

- Use iOS system text styles. SF Pro is the Latin UI family and PingFang SC is the Chinese system fallback.
- UI navigation, buttons, style names, states, and explanatory copy never use a decorative serif face. A supplied brand wordmark may keep its own artwork.
- Prefer short, direct Chinese labels. Never shrink critical text below `label-sm` to fit more controls.
- Preserve Dynamic Type and allow two-line labels where necessary instead of truncating the task meaning.

### Shape and Spacing

- Use an 8 pt primary spacing rhythm with 4 pt optical adjustments. Standard horizontal margins are 16–20 pt.
- Use continuous corners that harmonize with iPhone hardware: 24–28 pt destination tiles and control groups, 20–24 pt media, and system-derived button radii.
- Reserve pills for compact statuses. Do not turn every control into an isolated capsule.
- Avoid a screen full of floating capsules. One contained decision area is calmer than many detached buttons.
- On tablets, widen the image-and-decision composition without introducing more simultaneous choices.

### Motion

- UI motion communicates state changes only: navigation, style selection, preview replacement, source-linked Sheet transition, progress, and result arrival.
- Keep transitions short and reversible; never animate the photo merely to advertise the product.
- Dynamic results default to a poster frame with an explicit play control. Respect Reduce Motion and the system autoplay preference; user-created media remains playable through an explicit action.

## Interaction States

```text
home
  ├─ chooseOptimize → preparingSource → tapOptimize → applyingOrConfirming → staticReady
  ├─ chooseStyle → preparingSource → tapOutcomeStyle → applyingOrConfirming → staticReady
  ├─ chooseCleanup → preparingSource → tapCleanup → applyingOrConfirming → staticReady
  └─ chooseMotion → preparingSource → tapMotion → generatingOrConfirming → motionReady
```

- Every async response binds to the current `CreationTask`, selected `CreationCapability`, `creationIntent`, source, style/effect version, and request identity.
- Failure preserves the last safe image and selected capability. It explains the failure without recommending, substituting, or automatically switching capabilities.
- A generative capability being unavailable never blocks another capability. Generation availability is checked only after the user selects a generative capability.
- An applied result may be replaced internally. The user does so by tapping another visible option; the system chooses none automatically.

## Accessibility and Responsive Rules

- Interactive targets are at least 44 × 44 pt and remain reachable above safe areas and the keyboard.
- Text and essential icons meet WCAG AA contrast against their actual surfaces.
- Selection is never communicated by color alone; add border, label, or semantic state.
- Voice recording has explicit start, recording, stop, reviewing, permission-denied, and failure states.
- Screen readers announce source/preview/result identity, selected task and style (where applicable), generation unavailability/status, and whether an action may upload or consume quota.
- At large text sizes, the image may shrink before actions become clipped or horizontally scrollable.

## Explicitly Excluded

- generic editor/tool/parameter navigation;
- no-label tool icons and hidden gestures required to continue;
- permanent generic command, manual, atmosphere, or lighting docks unrelated to the chosen task;
- photo strips, group scope, batch controls, or multi-photo ordering;
- automatic work merely from entering a workspace, without tapping a named choice;
- automatic capability selection, recommendation, ranking, highlighting, combination, substitution, fallback, upload, generation, or charging;
- generative removal outside the object or region the user explicitly selected;
- a shared task-ready screen that exposes actions from multiple tasks;
- prompt, voice, reference, model, provider or parameter controls in the primary style workspace;
- decorative complexity that competes with the photo.

The canonical product behavior remains [MVP Spec](docs/product/mvp-spec.md). This file owns visual hierarchy and interaction presentation only; it does not declare implementation completion.
