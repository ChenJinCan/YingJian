# Issue tracker: Local Markdown

映见的需求、Spec 和 tickets 保存在仓库本地 `.scratch/` 中，不创建远程 issue。GitHub 远端只用于代码同步，除非用户另行明确授权。

## 约定

- 每个功能使用一个目录：`.scratch/<feature-slug>/`。
- Spec 保存为 `.scratch/<feature-slug>/spec.md`。
- 实现 tickets 分别保存为 `.scratch/<feature-slug>/issues/<NN>-<slug>.md`，从 `01` 开始编号；不得合并为单一 tickets 文件。
- 每个 ticket 顶部使用 `Status:` 记录状态，角色字符串见 `triage-labels.md`。
- 评论和讨论历史追加到文件末尾的 `## Comments`。

当技能要求“发布到 issue tracker”时，在对应 `.scratch/<feature-slug>/` 下创建 Markdown 文件。
