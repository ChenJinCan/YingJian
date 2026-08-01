# 遥测事件目录

事件定义的唯一事实源是 `lib/observability/analytics_event.dart`。

| 事件 | 目的 | 允许参数 |
| --- | --- | --- |
| `app_opened` | 验证应用启动 | 当前安全页面（如有） |
| `screen_viewed` | 页面漏斗 | `screen` |
| `editor_opened` | 编辑器入口转化 | `source`, `screen` |
| `diagnostics_preference_changed` | 诊断授权变化 | `action`, `result` |
| `review_eligible` | 评分策略漏斗 | `version_bucket` |
| `review_suppressed` | 评分抑制原因 | `reason`, `version_bucket` |
| `review_request_attempted` | 系统评分请求尝试 | `version_bucket` |
| `review_request_unavailable` | 系统评分不可用 | `reason`, `version_bucket` |
| `review_store_link_opened` | 永久评分入口使用 | `version_bucket` |

任何新增事件都必须先说明产品问题、保留周期和允许参数，并增加白名单测试。禁止通用 `log(String message)`、任意属性 Map 和服务端下发事件名。
