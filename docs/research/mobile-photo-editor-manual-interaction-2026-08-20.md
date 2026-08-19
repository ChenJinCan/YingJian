# 主流移动修图 App 的手动编辑交互

> 调研日期：2026-08-20
> 证据范围：官方帮助、官方产品页和官方 App Store 商品页。步数统一从“照片已经打开”开始计算，不计算选图；拖动不计为点击。官方材料不能证明的现行界面细节标为“未证”，不使用第三方教程补齐。

## 结论

映见不应该再设计“四个手动分类 → 能力列表 → 参数”的三级入口。主流产品真正值得借鉴的不是分类名称，而是三条共同规律：

1. 图片始终是主角；当前只展开一个工具或一组紧密相关参数。
2. 常用能力在编辑入口后直接可见；完整工具库才需要分组或搜索。
3. AI 和手动最终作用于同一张可继续编辑的照片，但并不需要把 AI 的内部过程展示给用户。

映见建议采用比 Apple Photos 和 Google Photos 少一层的路径：

```text
照片 → 手动 → 常用能力 → 拖动
```

也就是进入手动后直接露出 `亮度、色温、肤质、脸型、裁剪、更多` 等少量动态常用项；点击任意项后只出现一个滑杆或一个直接画布手势。不要先要求用户选择“基础 / 人像 / 局部 / 构图”。

## 对照表

| App | 到单个手动参数 | 编辑层首屏 | 工具组织 | 单参数交互 | 确认方式 | AI 与手动 |
|---|---:|---|---|---|---|---|
| Apple Photos | 3 次：编辑 → 调整 → 参数 | Styles、Portrait、Adjust、Crop、Clean Up，按照片和设备变化 | 少量一级模式；调整参数横向排列 | 点参数后拖一条滑杆 | 参数无单独确认；离开编辑时 Done | 自动增强就在 Adjust 内；Clean Up 也是同一编辑页入口 |
| Google Photos | 3 次：编辑 → Adjust/Lighting → 参数 | 建议项与工具分类 | Android 为 Markup、Filters、Crop、Adjust、Actions；iOS 为 Actions、Filters、Lighting、Color；另有工具搜索 | 点参数后拖 dial | 工具 Done，最后 Save | 建议在编辑首层；对话编辑从同一个 Edit 入口进入，但生成后仍保存到照片 |
| Lightroom Mobile | 约 3 次：照片 → Edit → Light/Color 等；若照片已在 Detail view，则 2 次 | Actions、Presets、Crop、Edit、Masking、Remove | 专业面板，再按 Light、Color、Effects、Detail、Optics 等分组 | 多个明确命名的滑杆 |普通滑杆不逐项确认；Crop、Preset 等子模式使用勾选 | Actions 给情境化建议；Auto 直接改同一组手动滑杆，之后可继续精调 |
| Snapseed | 2 次：Tools → Tune Image，再用上下手势选参数 | Tools；官方帮助把能力解释为 Tools 与 Filters | 工具平铺，进入后隔离当前工具 | 画布上下选参数、左右调数值 | 每个工具都要 Apply 或 Cancel；最后另行 Export | Automatic 是工具内自动结果，可继续用同一手势微调；没有已证的对话式 AI 主流程 |
| 醒图 | 未证 | 官方材料只证明“一键美颜、精准美型、一站式修图” | 未找到足以核对当前移动版层级的一手说明 | 未证 | 未证 | 官方强调一键能力与细节微调并存，但不足以证明二者如何衔接 |
| 美图秀秀 | 未证 | 官方材料证明人像美容、配方、滤镜调色和 AI 工具并存 | 能力范围极广；官方商品页不能证明当前移动端具体层级 | 未证 | 未证 | AI 与传统工具并存已证，但不能据商品页断言它们共用同一参数状态 |

## 分项证据

### Apple Photos：最值得借鉴默认手动形态

Apple 的官方 iPhone 指南给出的路径是“打开照片 → Edit → Adjust → 选择 Exposure 等参数 → 拖动滑杆”，编辑页底部仅露出少量模式。参数调整过程中不需要逐项应用，最后才用 Done 保存；编辑中支持多步撤销和重做，保存后也能恢复原图。
来源：[Apple：编辑照片与视频](https://support.apple.com/guide/iphone/edit-photos-and-videos-iphb08064d57/ios)、[Apple：撤销和恢复照片编辑](https://support.apple.com/guide/iphone/undo-and-revert-photo-edits-iph2413db0ab/ios)

可借鉴：

- 一次只让用户看一个参数和一条滑杆；
- 自动增强和手动调整共处一个编辑上下文；
- 始终可撤销，用户不需要理解底层编辑结构。

不建议照搬：Apple 仍要求最后点 Done；映见已有事务历史时，可以自动提交并靠撤销兜底。

### Google Photos：值得借鉴“建议 + 搜索”，不必照搬两次确认

Google 官方帮助把工具按功能归类。Android 当前公开分类为 Markup、Filters、Crop、Adjust、Actions；iOS 为 Actions、Filters、Lighting、Color。调整亮度等参数的路径是进入编辑、进入对应分类、选择参数、拖动 dial。Google 还允许直接搜索 Brightness 等工具，减少用户记忆分类的成本。
来源：[Google Photos Android 编辑帮助](https://support.google.com/photos/answer/6128850?co=GENIE.Platform%3DAndroid&hl=en)、[Google Photos iPhone/iPad 编辑帮助](https://support.google.com/photos/answer/6128850?co=GENIE.Platform%3DiOS&hl=en)

Google 的建议编辑直接出现在编辑入口；对话编辑也从 Edit 进入，用户输入或说出要求后保存结果。不过官方流程包含工具内 Done 和最终 Save，确认层次比映见目标更重。

可借鉴：

- 默认显示与当前照片相关的常用项，而不是固定展示全部工具；
- “更多”里提供搜索，用户可直接找“提亮”“瘦脸”，不必先猜分类；
- AI 结果回到普通照片编辑上下文。

### Lightroom Mobile：完整但不适合作为默认层

Adobe 官方文档显示，Lightroom 的 Detail view 同时提供 Actions、Presets、Crop、Edit、Masking、Remove；Edit 里再分 Light、Color、Effects、Detail、Optics 等专业面板。它适合熟悉术语、需要精确控制的用户，不是最低认知成本范本。
来源：[Adobe：Lightroom Mobile iOS 编辑](https://helpx.adobe.com/lightroom-cc/using/edit-photos-mobile-ios.html)、[Adobe：移动端工作区](https://helpx.adobe.com/lightroom/mobile/get-started/workspace-overview.html)

它最有价值的衔接是：Actions 给出 AI 情境建议，而 Edit 中的 Auto 直接调整 Exposure、Contrast、Highlights、Shadows、Whites、Blacks、Saturation、Vibrance 等现有滑杆；用户之后仍可进入这些滑杆继续手调。

可借鉴：AI 与手动共享参数结果。
不建议照搬：把六个专业一级面板和更多二级参数直接搬到映见默认界面。

### Snapseed：手势很直接，但逐工具确认偏重

Snapseed 官方帮助给出的路径是：打开图片后点 Tools，选择 Tune Image；在图片上上下滑选择 Brightness、Contrast、Saturation 等参数，左右滑调整数值。它把控制直接放在画布上，避免永久占据大量屏幕空间。
来源：[Snapseed：开始使用 Tools 与 Filters](https://support.google.com/snapseed/answer/6155517?hl=en)、[Snapseed：Tune Image](https://support.google.com/snapseed/answer/6157802?hl=en)

但每个工具需要 Apply 或 Cancel，最后还要 Export；这与映见“改完即生效、不满意就撤销”的目标相反。Snapseed 的非破坏 Stacks 和多步撤销值得借鉴，逐工具确认不值得借鉴。
来源：[Snapseed：添加滤镜效果](https://support.google.com/snapseed/answer/3114215?hl=en)、[Snapseed：撤销、重做、恢复](https://support.google.com/snapseed/answer/6181627?hl=en)、[Snapseed：保存与导出](https://support.google.com/snapseed/answer/6155519?hl=en)

### 醒图与美图秀秀：只作为能力范围参照

醒图官方 App Store 页面宣称“一键美颜、精准美型、功能全面、无需切换、一站式满足”，官网还宣传一键调色和批量处理；但这些公开材料没有给出当前移动版从打开照片到某个手动滑杆的可靠步骤，因此不能据此断言它的 UI 比 Apple 或 Google 更简单。
来源：[醒图 App Store](https://apps.apple.com/cn/app/id1500526240)、[醒图官网](https://www.retouchpics.com/)

美图秀秀官方 App Store 页面证明其同时提供人像美容、配方、专业滤镜调色、AI 修图和 AI 美容。它适合核对映见是否漏掉用户熟悉的能力名称，却不适合作为“简洁手动 UI”的已证范本。
来源：[美图秀秀 App Store](https://apps.apple.com/cn/app/id416048305)

## 映见应采用的手动交互

### 默认只保留两层

```text
手动
  → 常用能力横排
    → 当前能力的一个控件
```

手动面板打开后，不先显示分类，直接显示最多 5 个能力加一个“更多”：

```text
亮度　色温　肤质　脸型　裁剪　更多
```

这 5 个能力不是永久固定，可以根据照片内容、刚刚的 AI 修改和用户最近使用动态排序。点“亮度”后，能力行可以缩成标题，只保留：

```text
亮度                 0
────────●────────
```

- 拖动实时生效，松手成为一次可撤销修改；
- 点数值或双击能力名归零；
- 下滑或点图片收起，不出现“应用 / 完成”；
- 撤销固定可见，承担用户反悔，而不是提前要求确认。

### 完整能力只放进“更多”

“更多”不是新的四级工具树，而是一页可搜索的能力库：

```text
搜索：想调什么？
最近使用
为这张照片推荐
全部能力（按少量语义分段）
```

分段只帮助扫描，不是进入工具前必须经过的导航。搜索“脸”“暗”“背景”等自然词即可直接打开对应能力。

### AI 与手动只保留一个连接点

AI 改完后不展示参数清单，也不弹“去手动调整”。用户打开手动面板时：

- AI 刚改过的能力自然排到最前；
- 打开的就是当前真实数值；
- 用户继续拖动，仍形成普通可撤销修改；
- UI 不标记“AI 参数”或“手动参数”。

因此用户感知到的完整逻辑只有：

```text
想自己改 → 点手动 → 点一个能力 → 拖动
想让 AI 改 → 说一句 → 图片变化
不满意 → 撤销
```

## 产品决定建议

1. 删除“四个一级分类”作为默认入口。
2. 手动打开后直接露出动态常用能力，目标是从已打开照片到拖动不超过 2 次点击。
3. 每次只显示一个主要控件；复杂工具才临时接管画布。
4. 完整能力通过“更多 + 搜索”获得，不靠用户记忆分类。
5. 不增加应用、完成或 AI 结果确认；用事务级撤销保证安全。
6. AI 与手动共享同一数值状态，AI 改过的能力只通过排序靠前体现。
7. 醒图和美图秀秀需要另做同版本真机走查后，才能把具体层级写成事实；当前一手公开资料只能支持能力范围判断。
