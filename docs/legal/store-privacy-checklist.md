# 隐私与商店合规清单

## 已在应用内完成

- 中英文隐私政策与使用条款可从设置页访问。
- 匿名诊断默认关闭，并在开关说明中列出用途。
- Firebase 自定义遥测使用事件与参数白名单。
- 评分入口不把用户导向自建好评筛选页面。

## 上线前阻断项

- 为隐私政策和支持页提供长期可访问的公开 HTTPS URL。
- 在 `release/legal-policy.yaml` 填入公开 URL 和支持联系方式。
- 对照真实 Firebase 配置、图片选择器、未来云端 AI 和其他 SDK 完成 Apple App Privacy 问卷。
- 对照所有第三方 SDK 完成 Google Play Data Safety；不能只声明映见自己直接处理的数据。
- 在每个启用的商店 locale 重新读取并验证隐私政策 URL。
- 确认 Apple 使用标准 EULA；若改用自定义 EULA，必须单独获批并保存地区快照。
- 获得 iOS App Store ID 后，通过构建参数 `--dart-define=IOS_APP_STORE_ID=<id>` 配置永久评分入口。

发布预检会运行 `scripts/check_legal_setup.rb`。字段未配置或商店声明未验证时必须保持失败，不能把应用内 Markdown 当作公开隐私政策 URL。
