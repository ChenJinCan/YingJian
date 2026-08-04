# 映见移动端 MVP 交互原型

> THROWAWAY PROTOTYPE — 仅存在于 `codex/mobile-prototype-mvp-flow` 分支，不进入生产路由。

要验证的问题：移动端用户能否完成“选 1–6 张 → 三套本地推荐 → 整组调整 → 单张精修 → 返回整组 → 批量导出与失败重试”。

## 启动

```sh
flutter run -t lib/main_mvp_prototype.dart
```

指定初始结构：

```sh
flutter run -t lib/main_mvp_prototype.dart \
  --dart-define=YINGJIAN_PROTOTYPE_VARIANT=B
```

- A：结果优先，全屏预览、横滑配方和底部拇指工具区。
- B：组图优先，移动联系表与底部检查器。
- C：引导优先，一屏只回答一个问题。

三个结构只通过启动参数切换，不在用户界面中暴露调试控件。所有业务状态只保存在内存，重启应用即重置。

## 移动端验证范围

- 竖屏 SafeArea 和底部手势区域。
- Navigator 返回栈。
- 相册式三列选择、固定底部主操作和 PageView 横向切换方案。
- 长按主图查看原图。
- 整组/当前照片编辑范围。
- 导出确认 Bottom Sheet。
- 部分失败和单项重试。
- iOS/Android 模拟器布局与可访问语义。

示意照片来自远程占位资源，不进入质量语料，也不能证明真实滤镜、人像或导出质量。
