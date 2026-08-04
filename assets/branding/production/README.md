# 映见品牌资产包

> 基于 v5 开放光环。状态：可用于备案和视觉评审，尚未写入 iOS / Android 平台资源目录，也未上传商店。

## 交付清洁度

- 最终 PNG 未发现可见水印。
- 文件已重新编码，不包含 Codex、OpenAI、生成提示、生成器注释、EXIF、C2PA 或 PNG 文本元数据。
- PNG 仅保留图像头、像素数据和结束块；透明版本仅通过 RGBA alpha 表达透明度。

## 文件用途

| 文件 | 规格 | 用途 |
|---|---:|---|
| `app-icon-ios-1024.png` | 1024 × 1024，RGB，不透明 | iOS / iPadOS App Icon 与阿里云备案图标 |
| `app-icon-google-play-512.png` | 512 × 512，RGBA | Google Play 商店图标 |
| `android-adaptive-foreground-432.png` | 432 × 432，RGBA | Android 自适应图标彩色前景层 |
| `android-adaptive-background-432.png` | 432 × 432，RGB，纯白 | Android 自适应图标背景层 |
| `android-adaptive-monochrome-432.png` | 432 × 432，RGBA | Android 主题图标单色前景层 |
| `brand-mark-color-transparent-1024.png` | 1024 × 1024，RGBA | 品牌宣传、网页、海报和视频中的透明彩色标 |
| `brand-mark-berry-transparent-1024.png` | 1024 × 1024，RGBA | 浅色背景上的深莓色单色标 |
| `brand-mark-ivory-transparent-1024.png` | 1024 × 1024，RGBA | 深色或摄影背景上的象牙白单色标 |
| `brand-tile-light-1024.png` | 1024 × 1024，RGB，纯白 | 浅色品牌头像、占位图和展示底图 |
| `brand-tile-dark-1024.png` | 1024 × 1024，RGB | 深色品牌头像、片尾和展示底图 |

## 平台规则

- Apple 图标使用不透明方形母版，不自行添加圆角；系统负责最终蒙版。
- Google Play 商店图标使用 512 × 512 的 32-bit PNG，保持文件小于 1 MB。
- Android 自适应图标使用 108 dp 的前景与背景层；本包用 432 px 表示 108 dp。彩色主体最大边为 248 px，位于 264 px（66 dp）安全区内。
- Android 单色层只提供 alpha 轮廓，实际颜色由系统主题决定。
- 宣传物料优先使用透明彩色标；背景过杂或对比不足时改用深莓色或象牙白单色标。

## 品牌色

- 深莓色：`#711744`
- 深莓背景：`#42162E`
- 暖杏桃：`#FF9E82`
- 柔粉：`#F5B5C5`
- 淡紫：`#BFA6E8`
- 中性白：`#FFFFFF`

## 禁止事项

- 不拉伸、压扁、旋转或改变顶部开口关系。
- 不给品牌标追加花、珍珠、星芒、相机、描边或投影。
- 不把透明品牌标直接当作 Apple 商店图标。
- 不在低对比背景上强行使用彩色标；应切换单色版本。
- 不把 Android 前景层预先裁成圆形或圆角方形。

## 官方规格依据

- [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
- [Google Play preview assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en)
