# 隐私与商店合规清单

最近一次只读回读：2026-08-04 12:45（Asia/Shanghai）。详细证据与未完成项见
[`store-state-snapshot-2026-08-04.md`](store-state-snapshot-2026-08-04.md)。商店状态会变化，任何构建、上传或提交前必须重新读取，不能把本快照当作新候选基线。

## 已在应用内完成

- 中英文隐私政策与使用条款可从设置页访问。
- 匿名诊断默认关闭，并在开关说明中列出用途。
- Firebase 自定义遥测使用事件与参数白名单。
- 评分入口不把用户导向自建好评筛选页面。

## 上线前阻断项

- [x] 已部署长期可访问的公开隐私政策、支持页与使用条款：
  - `https://everyday-apps-websites.baby-animals-ai-cjc.workers.dev/privacy`
  - `https://everyday-apps-websites.baby-animals-ai-cjc.workers.dev/support`
  - `https://everyday-apps-websites.baby-animals-ai-cjc.workers.dev/terms`
- [x] 已在 `release/legal-policy.yaml` 填入公开 URL 和支持联系方式 `865525900@qq.com`。
- [x] 已对照 Firebase Analytics、Crashlytics、Performance 与应用行为完成并发布 Apple App Privacy：仅声明大致位置、设备 ID、产品交互、崩溃、性能及其他诊断数据；均不关联身份、不用于跟踪。
- [x] 已对照 Firebase Analytics、Crashlytics、Performance 与应用行为完成 Google Play Data Safety；Publishing overview 将其列为尚未提交审核的变更。
- [x] 已完成 Google Play IARC 内容分级问卷；相关变更尚未提交审核。
- [x] 已回读唯一启用的 Apple 商店 locale `Chinese (Simplified)`，隐私政策 URL 与公开页面一致。
- [x] 已确认 Apple 使用标准 EULA；若改用自定义 EULA，必须单独获批并保存地区快照。
- [x] 已创建 App Store 草稿，Apple ID 为 `6797692747`，并作为 `IOS_APP_STORE_ID` 默认值配置永久评分入口；构建时仍可通过同名 `--dart-define` 覆盖。
- [ ] App Store 1.0 仍缺年龄分级、类别、截图、描述、关键词、Support URL、版权、审核联系信息和候选构建；当前发布控制为审核通过后自动发布，提交前必须取得明确授权并重新确认。
- [ ] Google Play 初始设置为 10/11，默认商店列表仍未完成；`Send app for review` 当前不可用。
- [ ] Firebase iOS 应用设置中的 App Store ID 与 Team ID 尚未填写；不影响本地 SDK 身份检查，但应在正式 Apple 候选前确认是否需要补齐。

发布预检会运行 `scripts/check_legal_setup.rb`。字段未配置或商店声明未验证时必须保持失败，不能把应用内 Markdown 当作公开隐私政策 URL。
