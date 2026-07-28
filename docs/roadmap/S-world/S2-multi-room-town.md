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

### S2.2 `[ACTIVE baseline]` 完整住宅

增加厨房、卧室、走廊，形成第一套住宅。

- `[DONE graph/runtime baseline]` `data/world_locations.json` 已声明客厅、厨房、卧室
  的资源、入口、出口、共享 Cast 出生点和场景描述；`WorldLocationCatalog` 对出口
  目标与入口做 fail-closed 查询，`WorldLocationLoader.travel_to/travel_via` 可在不
  破坏当前地点的前提下切换房间。
- `[DONE generated room baseline]` 厨房与卧室已有独立 Recipe/Manifest；厨房使用
  KayKit Restaurant Bits 的冰箱、水槽、烤箱、餐桌和餐椅，卧室复用已验收的
  CC0 家具并新增真实双人床。两份布局均通过边界、重叠和桌面跟随约束编译。
- `[DONE semantic scope baseline]` `SemanticWorld` 为生成物体记录 `location_id`，
  LLM 的物体列表与自然语言快照只暴露当前房间，避免厨房角色继续规划客厅沙发。
- `[DONE cast handoff baseline]` 每次旅行重新挂载共享 Cast 并应用地点出生点；
  运行时角色适配器采用引用计数，旧地点宽限释放不会误删新地点的角色绑定。
- `[DONE runtime/visual acceptance]` `multi_room_home_check.gd` 已通过三房间模型
  覆盖率、语义隔离、Cast、导航和非法旅行原子性；客厅剧情、体验模式与关键路点
  回归通过。厨房和卧室采用三面墙玩偶屋结构，并通过 1280×720 Metal 截图验收。
- `[NEXT]` 增加可见走廊/门交互和玩家触发器；跨地点角色位置、所在地点及物体状态
  持久化属于 X1 v2 配套验收。

### S2.3 `[NEXT]` 独立地点接入

接入庭院和"晓光忆时"作为独立地点，不直接替换客厅。

### S2.4 `[LATER]` 公共地点

增加街道、咖啡馆、公园等公共地点。

### S2.5 `[LATER]` 场景流送与离屏模拟

实现场景流送、远景代理、跨场景导航和角色离屏模拟。

## 建议执行顺序

住宅三房间的生成与地点图基线已经建立；下一步补门/走廊触发器、动态验收与 X1
位置迁移，再建设街道，否则角色日程与离屏模拟会反复返工。

## 相关节点

- [T2 语义世界与空间协议](../T-runtime/T2-semantic-world.md) — 跨场景位置图与语义查询
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 日程需要跨场景日程
- [X1 存档和迁移](../X-engineering/X1-save-migration.md) — 存档需支持跨场景位置

> 相关文档：[S 分支总览](./README.md) · [分支依赖关系](../99-dependencies.md)
