# 现有应用基础框架审计

审计日期：2026-08-01。来源为本机当前的 `NextNote`、`natureid` 和 `animalplant` 主仓库代码，不以旧文档或包依赖名称代替实际实现。

## 共同模式与采用决定

| 能力 | 三款应用现状 | 映见决定 |
| --- | --- | --- |
| 应用外壳 | 都使用 `MaterialApp`、全局 `navigatorKey`、`onGenerateRoute` | 采用，路由映射集中在 `AppRouter` |
| 可观察状态 | 都以 `ChangeNotifier` 为主，且依赖 `provider`；旧项目还大量使用全局 `AppState/AppStore` | 采用 ChangeNotifier/provider，不复制全局可变单例；从根部注入 |
| 启动流程 | 都使用 `runZonedGuarded`；NatureID 进一步把首屏前准备与延迟初始化拆开，并已有单测 | 采用 `StartupCoordinator`，关键设置加载后再首屏，慢服务放到延迟列表 |
| 本地化 | 都依赖 `flutter_localizations` 且设置 `generate: true`，但历史生成方案不同 | 采用 Flutter 官方 gen-l10n；首批中文、英文 |
| 轻量设置 | 都使用 `shared_preferences` | 采用，持久化主题模式和语言覆盖 |
| 主题 | 都集中定义主题，并让主题状态触发应用重建 | 采用 `AppTheme + AppSettings` |
| 首屏配置 | NextNote、NatureID 都设置方向、透明状态栏和 100 MB 图片缓存 | 采用；作为启动关键步骤 |
| 测试 | 都有 Flutter 单测/Widget 测试；NextNote、NatureID 明确包含 integration_test | 采用单元、Widget、integration_test 三层入口 |
| Firebase | 三者均有 Analytics、Crashlytics、Performance | 已通过独立项目 `yingjian-ce1d1` 接入，并保持默认关闭、用户显式开启和供应商失败不阻塞启动 |
| Wiredash | 三者均使用，但项目 ID、隐私设置和页面包装方式不同 | 暂缓；不得复制其他应用凭据 |
| EasyLoading | 三者均有历史使用 | 不作为新项目底层标准；先使用页面内明确状态，避免全局遮罩耦合 |
| 图片选择 | 三者都依赖 `image_picker` | 已在“照片导入”纵向切片接入；关闭完整元数据请求，并立即复制到应用自有目录，不能跨会话保存选择器临时路径 |
| 数据库 | NextNote、NatureID、animalplant 分别存在不同 SQLite/Drift/Hive 组合 | 不选统一数据库；等项目恢复、草稿和素材索引的数据模型确定后决策 |
| 网络 | 三者都有 `http`，NatureID 另有 Dio | 当前不添加；本地编辑 MVP 没有网络调用，云端 AI 出现真实 seam 后再接入 |

## 没有照搬的历史模式

- 不复制 `AppState.instance`、`AppStore.instance` 和全局 `BuildContext`。它们在成熟应用中承载大量历史调用，但会扩大隐式依赖和测试初始化成本。
- 不复制任何其他应用的 Firebase、Wiredash、RevenueCat、广告或商店凭据；映见只使用独立项目 `yingjian-ce1d1` 的平台配置。
- 不复制 `managers/`、`services/`、`utils/` 空目录；只有真实 Module 和 Adapter 出现时才建立目录。
- 不把数据库、HTTP 客户端或图片插件仅作为“以后可能用”加入依赖。
- 不复制会在生产错误页显示完整异常和堆栈的 `ErrorWidget.builder`。

## 当前映见基础依赖

- Flutter SDK：UI 和运行时。
- `flutter_localizations` + `intl`：官方本地化生成和运行时代理。
- `provider`：从应用根部注入可观察状态。
- `shared_preferences`：主题和语言等非敏感轻量设置。
- `image_picker`：用户主动选择 1–6 张照片；不请求完整元数据。
- `path_provider`：把照片副本和项目快照保存在应用支持目录。
- Firebase Analytics、Crashlytics、Performance：匿名诊断的供应商实现，默认关闭并由用户显式开启。
- `flutter_test` + `integration_test`：Module、Widget 和未来真机链路验证。

新增依赖必须对应当前用户能力或已存在的第二个 Adapter，不能为了目录完整而引入。
