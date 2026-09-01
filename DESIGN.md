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

### 官方风格 V1

同一源照片、同一构图下的六个首批方向；风格差异只来自色彩、光线、质感和氛围，不改变人物身份与结构。

![映见官方风格 V1](docs/design/yingjian-official-style-library-v1.png)

## Interactive Mobile Prototype

本地可点击原型位于 `.scratch/prototypes/style-first-mobile/`。它验证的不是传统编辑器，也不是在定风格后再让用户选择结果类型，而是首页先按任务分流的四条独立路径：

```text
首页
├─ 优化照片 → 选图片 → 本地优化 → 静态结果
├─ 换风格 → 选图片 → 定风格 → 应用风格 → 静态结果
├─ 去背景 / 去杂物 → 选图片 → 语义背景或本地擦除 → 静态结果
└─ 做动态效果 → 选图片 → 服务可用时定风格、确认生成 → 动态结果
```

- 首页显示品牌与四个整块可点击的 iOS destination tiles：**优化照片**、**换风格**、**去背景 / 去杂物**、**做动态效果**。每个 tile 左侧是任务与一句结果说明，右侧是语义预览；不得使用重复满幅人像的海报墙。
- 点击入口即确定任务；正式产品随后调用系统选图，原型中直接用样片模拟选图完成。
- `CreationTask=optimize|style|cleanup|motion` 是入口身份；`CreationIntent=apply|motion` 只选择静态/生成执行分支。旧 `apply` 草稿恢复为 `style`。
- 换风格与做动态效果可复用选图、官方风格和 AI 定风格能力，但不得复用一个可见的“双出口”页面。
- 优化照片只显示本地优化操作；换风格只显示 **应用风格**；去背景 / 去杂物只显示受支持的语义背景或本地擦除；做动态效果服务未接入时只显示不可用状态。
- 官方风格使用带可见名称的横向缩略图；`AI 定风格` 固定在当前风格标题右侧并替代无操作价值的“预览”标签，首次进入即可看见，点按后打开来源关联的系统式 Sheet。
- 生成确认只在服务接入后使用底部 Sheet，保留上传范围、权益与预计等待；当前未接入时不得上传、创建任务或收费。
- 静态结果使用媒体查看器；服务接入后的动态结果默认暂停并由用户明确播放。保存是主操作，分享走系统分享，返回当前任务不隐式切换任务。

运行方式及验证边界见 `.scratch/prototypes/style-first-mobile/README.md`。该原型是本地验证材料，不是 Flutter 实现或发布证据。

## Product Mental Model

The production experience starts from four explicit user tasks:

```text
优化照片：选图片 → 本地优化
换风格：  选图片 → 定风格 → 应用
去背景 / 去杂物：选图片 → 受支持背景或擦除
做动态效果：选图片 → 服务可用时定风格 → 生成
```

This is not a simplified editor. It is a task-first, style-led creation experience.

- **优化照片**, **换风格**, **去背景 / 去杂物**, and **做动态效果** are four stable top-level destinations, chosen before photo selection.
- **选图片** starts one creation from one read-only source photo within the chosen task.
- **定风格** is shared only by the style and motion tasks: the user may switch an official style or define one with text, voice, or a reference image.
- `CreationTask` is user identity; `CreationIntent` is the execution branch. Optimize, style, and cleanup are local static work; motion is independent generation.
- Cleanup currently supports semantic background/white-background handling and local erase only; it is not alpha cutout or unbounded generative removal. Motion currently has no service: it must not upload, create a task, or consume quota.
- When generation is connected, it still uses the source photo and style definition directly. It never requires a static apply or export first.

Do not expose a generic editor shell, all-purpose tool categories, parameter sliders, a “自己调” escape route, or a fixed set of three recommendations. Optimize and cleanup may expose only the task-specific local controls needed to complete their named result. Parameters may exist behind the interface only as validated execution details.

## Experience Principles

1. **The image is the interface.** The source, preview, or result owns most of the screen and never moves merely because a transient control opens.
2. **One decision at a time.** Choose the task first; every later state asks only for the next decision in that branch.
3. **Style is the user language.** Names, visual examples, plain-language descriptions, and references describe a desired result; tool names do not.
4. **AI clarifies instead of taking over.** AI returns one understandable style definition and a trustworthy preview. It does not create hidden work or automatically start generation.
5. **State is honest.** Preview, applied result, generation task, and exported media are visually and verbally distinct.
6. **Calm beats density.** Fewer surfaces, low visual noise, short labels, and generous space matter more than exposing every capability.

## iOS Interaction Baseline

- Use a single `NavigationStack`: Home is the root, and each task owns one workspace route. Confirmation, progress, and result are phases inside that workspace rather than a stack of synthetic pages.
- Production photo selection uses system `PhotosPicker`, single image only. `CreationTask` is fixed before the picker appears; `CreationIntent` is derived from it; cancel returns to Home without creating an empty draft.
- Use system navigation, edge-back behavior, semantic colors and system text styles. UI text uses SF Pro with PingFang SC fallback; decorative serif type is limited to a supplied brand asset, never navigation, buttons, states, or style names.
- Liquid Glass belongs only to the functional layer: navigation controls, one continuous bottom control group, and temporary Sheet surfaces. Photos, task tiles, style thumbnails, and other content surfaces never become Glass.
- Standard controls are at least 44 × 44 pt; prominent actions are at least 52 pt high. Every custom control has a visible press state and an accessibility label.
- The interface adapts to Dynamic Type, Bold Text, Increase Contrast, Reduce Transparency, and Reduce Motion. At accessibility sizes, content scrolls or control regions grow; labels are not shrunk or clipped.
- Browser prototypes approximate iOS geometry only. System picker, native share UI, real video playback, haptics, interactive edge-back, material rendering, and final safe-area behavior require Simulator and physical-device validation.

Platform guidance: [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Information Architecture

### Home

- Show exactly four destination tiles: **优化照片** — “调亮、清晰、增强质感”；**换风格** — “日系、胶片、插画、电影感”；**去背景 / 去杂物** — “抠图、白底、清理路人杂物”；**做动态效果** — “让静态照片自然动起来”。每张整卡均为点击目标；不得把入口藏到加号、标签栏或菜单中。
- Tiles use the standard content layer, continuous 24–28 pt corners, concise secondary copy, and a small semantic preview. They may wrap and scroll at accessibility sizes; they are not full-bleed posters and do not use Glass.
- Selecting a destination fixes `CreationTask=optimize|style|cleanup|motion`, from which `creationIntent=apply|motion` is derived, before the system photo picker opens.
- Returning from the picker without a photo stays on Home. Selecting a photo creates a draft in the chosen branch; it never silently replaces or deletes another draft.
- If drafts are restored, each resume surface retains its original `CreationTask` identity. Historic `apply` drafts migrate to `style`; a draft cannot reopen as optimize or cleanup by inference.
- Settings remains secondary. Do not add a tab bar, creation templates, camera placeholders, community content, or promotional modules to the main path.

### Task Workspace

Each task owns its workspace state. The static/creation branches may share layout components, but never share one visible decision surface. Each workspace has three layers:

1. **System navigation:** Back, inline task title, and at most one contextual trailing action.
2. **Image stage:** the complete source, style preview, static result, or dynamic result on a stable media canvas.
3. **Bottom control layer:** the task's current action and one outcome action inside the safe area. Style and motion tasks may show current style, named style rail and AI entry; optimize and cleanup show only their supported local actions.

Keep the image stage stable across all states. Text, voice, reference selection, consent, and failures use system-style sheets or inline status that preserve the image context.

### Result State

- A static result uses a media viewer with primary **保存到照片**, system **分享**, and a task-appropriate secondary action.
- A dynamic result, after the service is connected, uses native video playback semantics with primary **保存视频**, system **分享**, and secondary **换风格**. It does not autoplay.
- Result dismissal uses an explicit close control labeled “关闭并返回首页”; a back chevron must never jump to Home.
- While a dynamic result is playing, the central pause control fades after about 1.5 seconds and returns when the user taps the media. Paused state keeps the play control visible.
- Result actions stay on the same visual surface; do not introduce an export editor or a long-lived results tab.
- **重新定风格** returns to `applyStyleReady` or (when available) `motionStyleReady` according to the current task. Returning never overwrites the source or deletes an earlier successful result.
- Switching among optimize, style, cleanup and motion is not a result action; the user returns to Home and deliberately enters the other task.

## Core Components

### Photo Stage

- Occupies roughly 60–72% of available height when controls are collapsed.
- Uses the source aspect ratio and `contain` behavior so the complete preview remains visible; restrained 20–24 pt continuous corners may frame the media canvas.
- Only essential status may overlay the photo: loading, unavailable preview, generation progress, or playback state.
- Original comparison is momentary and read-only. It is not an editing mode.

### Style Strip

- Only the style and motion task workspaces show this control. Optimize and cleanup do not expose a style rail merely to make their entry surfaces look alike.
- A horizontally scrollable Photos/Filters-style rail of 52–56 pt rounded previews with visible names.
- Each option has at least a 44 pt hit region and an unmistakable selected state using accent stroke plus checkmark/semantics, never color alone.
- Selecting a card switches the active style and requests the newest preview. Older responses cannot replace the latest selection.
- Do not group styles by editing tools. Optional curation uses human concepts such as mood, occasion, or visual character.

### Define Style Entry

- Only the style and motion task workspaces expose this entry.
- One fixed, first-view control labeled **AI 定风格** beside the current style heading. It does not depend on horizontal rail discovery.
- It opens a medium/large bottom Sheet that supports multiline text, voice, and one reference image without turning them into separate product modes.
- AI returns a readable style name, a short description, and one active preview. The user can accept it, revise the description, or return to official styles.
- Ask at most one essential clarification. Never show raw prompts, parameter chips, model selectors, or supplier controls.

### Branch Action

Show exactly one full-width primary action for the chosen task:

- In optimize: a local quality action for brightness, clarity, and texture.
- In `applyStyleReady`: **应用风格** creates the deterministic static result.
- In cleanup: only supported semantic background/white-background handling or local erase; never describe it as alpha cutout or unbounded generative removal.
- In `motionUnavailable`: no generation CTA. When the service is connected, `motionStyleReady` shows **生成动态** and opens the minimal generation confirmation.

Never render actions for two tasks on the same screen. The capabilities may share source and static safety contracts internally, but the interface preserves the task the user chose on Home.

### Generation Status

- Current state: the motion service is unavailable. Show one clear unavailable state and do not upload, create a task, charge quota, or fake progress.
- After the service is connected, state what will be uploaded, expected output, waiting time, cost or quota, and cancellation boundary before creating a task.
- After confirmation, replace the outcome area with one honest task status and the actions currently available. Keep the source or style preview visible while waiting. Do not fake percentages or create a second task when local waiting times out.

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
  ├─ chooseOptimize → preparingSource → optimizeReady → applyingLocalTask → staticReady
  ├─ chooseStyle → preparingSource → awaitingStyle
  │    → definingStyle | previewingStyle
  │    → applyStyleReady → applyingStyle → staticReady
  ├─ chooseCleanup → preparingSource → cleanupReady → applyingLocalTask → staticReady
  └─ chooseMotion → preparingSource → motionUnavailable
       └─ after service connection: awaitingMotionStyle → motionStyleReady
          → confirmingGeneration → generatingMotion → motionReady
```

- Every async response binds to the current `CreationTask`, `creationIntent`, source, style version, and request identity.
- Failure preserves the last safe image and offers one relevant recovery action.
- The three static task workspaces never become blocked merely because generation is unavailable; generation availability is evaluated only in the motion branch.
- Applying a style may be undone or replaced internally, but the default user recovery is the simpler **换风格** or **查看原图**.

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
- automatic generation after browsing or applying a style;
- transparent alpha cutout or unbounded generative removal under the cleanup task's current label;
- a shared task-ready screen that exposes actions from multiple tasks;
- separate product modes for text, voice, and reference input;
- decorative complexity that competes with the photo.

The canonical product behavior remains [MVP Spec](docs/product/mvp-spec.md). This file owns visual hierarchy and interaction presentation only; it does not declare implementation completion.
