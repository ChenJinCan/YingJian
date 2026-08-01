# Flutter 基础骨架

## 目标

基础骨架服务于 MVP 的三个稳定需求：快速迭代 UI、可预测的非破坏编辑状态，以及未来替换本地算法、商业 SDK 或云端模型时不污染页面代码。

## 依赖方向

```text
app（组装、主题、路由）
  └─ feature/presentation（页面与交互）
       └─ feature/application（用例与会话状态）
            └─ feature/domain（配方、值对象、不变量）

未来原生/云端 adapter ──> application 中真实存在的 seam
```

- `domain` 不依赖 Flutter UI、插件或供应商 SDK。
- `application` 可以使用 Flutter 的基础状态原语，但不导入 Widget。
- `presentation` 只通过 application Module 的 Interface 操作业务状态。
- `app` 只负责组装，不承载修图业务规则。
- iOS/Android 图像实现未来作为 Adapter 接入；在出现生产与测试两个 Adapter 前，不建立空接口层。

## 当前深 Module

`EditorSession` 是非破坏编辑会话 Module。调用方只需要理解：

- 当前 `recipe`；
- 一次性 `apply`；
- 手势期间 `beginAdjustment`、`preview`、`commitAdjustment`；
- `undo` 与 `reset`。

它内部隐藏历史栈和手势合并规则。一次滑块拖动无论产生多少预览值，都只形成一个撤销步骤。测试与页面通过同一个 Interface 验证行为。

## 暂不引入

- 不因只有两个页面就引入 go_router。
- 不因只有一个编辑会话就引入 Riverpod、Bloc 或 Redux。
- 不创建没有第二个 Adapter 的 repository/port。
- 不为尚未接入的遥测供应商创建空 bootstrap/error-reporter 转发层。
- 不创建通用 `utils`、`managers` 或 `services` 垃圾目录。

当深链路、跨页面共享状态、持久化项目恢复或真正的本地/云端双实现出现时，再按实际 seam 引入依赖和 Adapter。

## 新功能落位

- 用户可见页面：`lib/features/<feature>/presentation/`
- 用例、会话和任务编排：`lib/features/<feature>/application/`
- 配方、值对象和纯规则：`lib/features/<feature>/domain/`
- 跨 Feature 的应用组装：`lib/app/`
- 原生桥接：平台目录及对应 Feature 的 Adapter 目录，禁止直接散落在页面中。

测试文件镜像公开行为，不镜像内部目录数量。优先测试 Module Interface 和用户可见交互。
