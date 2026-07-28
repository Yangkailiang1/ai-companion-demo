# S2. 多房间、街道与小镇

> 所属分支：S. 场景与世界
> 节点编号：S2
> 状态：`[ACTIVE v0.8.9]`
> 依赖：T2（语义世界空间查询）、X1（存档跨场景位置）
> 最后更新：2026-07-28 | 基线程：v0.8.9

## 职责

将单一客厅扩展为可导航的多个地点，支持跨房间/跨场景的角色活动。

## 规划节点

### S2.1 `[DONE baseline v0.8.9]` WorldLocation 拆分

将客厅拆成可加载的 `WorldLocation`，加入入口、出口和出生点。

- `main.tscn/WorldRoot` 已由 `WorldLocationLoader` 统一装载地点，不再直接绑定
  `living_room.tscn`。
- 支持 `legacy` 与 `parametric` 两种地点实现；默认保持 `legacy` 回归基准，
  `AI_GAMES_WORLD_MODE=parametric` 可在真实主界面中启用参数化客厅。
- 地点热切换会先隐藏旧地点，保留两个 process frame 给角色异步协程收尾，再安全释放；
  非法模式或参数化场景加载失败会 fail-safe 回退旧客厅。
- 参数化客厅已包含导航、语义物体、交互组件、碰撞、五名角色、相机与 UI。
- `[DONE shared Cast]` 咕咕嘎嘎、诀和本地 Q 版角色生成器已拆成独立 PackedScene，
  legacy 与 parametric 地点均通过 `WorldCastAssembler` 实例化同一套运行时定义；
  参数化地点不再加载或抽取旧客厅。
- 旧客厅序列化的历史角色节点暂留作可回滚迁移数据，但会在入树前被共享 Cast 替换；
  S2.2 完成后可删除这些死数据与无用 ext/sub resources。
- 参数化地点在 X1 存档尚未加入 `location_id` 前使用地点声明出生点，避免把 legacy
  坐标错误恢复到生成布局；跨地点位置持久化需由 X1 v2 正式迁移。
- 生成 NavMesh 已增加显式上传和关键剧情路点连通性测试，家具链封路会阻止验收。

### S2.2 `[NEXT]` 完整住宅

增加厨房、卧室、走廊，形成第一套住宅。

首个增量先定义 `WorldLocation` 元数据、入口/出口与地点连接图，再生成厨房和卧室
Recipe；跨地点后恢复角色位置与物体状态属于 X1 配套验收。

### S2.3 `[NEXT]` 独立地点接入

接入庭院和"晓光忆时"作为独立地点，不直接替换客厅。

### S2.4 `[LATER]` 公共地点

增加街道、咖啡馆、公园等公共地点。

### S2.5 `[LATER]` 场景流送与离屏模拟

实现场景流送、远景代理、跨场景导航和角色离屏模拟。

## 建议执行顺序

共享 Cast 基线已经完成；下一步先完成住宅内部和地点连接图，再建设街道，否则
跨场景导航、存档和角色日程会反复返工。

## 相关节点

- [T2 语义世界与空间协议](../T-runtime/T2-semantic-world.md) — 跨场景位置图与语义查询
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 日程需要跨场景日程
- [X1 存档和迁移](../X-engineering/X1-save-migration.md) — 存档需支持跨场景位置

> 相关文档：[S 分支总览](./README.md) · [分支依赖关系](../99-dependencies.md)
