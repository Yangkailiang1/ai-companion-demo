# S2. 多房间、街道与小镇

> 所属分支：S. 场景与世界
> 节点编号：S2
> 状态：`[ACTIVE v0.8.9]`
> 依赖：T2（语义世界空间查询）、X1（存档跨场景位置）
> 最后更新：2026-07-29 | 基线程：v0.8.9

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
- `[DONE X1.2]` 参数化地点已接入 Schema v2 `location_id`：旧 v1 坐标只迁移到
  legacy 客厅，参数化角色在目标地点生成后恢复，避免跨布局错误传送。
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
- `[DONE cross-location persistence]` 角色所在地点/坐标和已加载、未加载房间的对象
  状态均可跨存档恢复；v1 迁移和坏存档保护通过独立 headless 合同测试。
- `[DONE visible portal baseline]` 四条出口边均有数据驱动的门洞、暖木门框、门扇、
  碰撞和“厨房/卧室/客厅”3D 门牌；玩家可点击门旅行，悬停与按下有视觉反馈。
  `WorldTravelPortal` 只持有稳定 `exit_id`，目标地点仍由 Catalog/Loader 解析，
  同时以 `traverse` affordance 注册到 `SemanticWorld`，可供后续角色规划复用。
- `[DONE portal safety/acceptance]` 退役地点会先停用全部门，阻止双击和两帧释放
  宽限期内的陈旧入口再次旅行；严格目录校验拒绝缺字段、坏向量、非正尺寸和重复
  语义 ID。四次旅行、三房间入口数量、出生点及 1280×720 Metal 画面均已验收。
- `[NEXT]` 增加真实走廊模块和玩家实体/第一第三人称控制器，把“点击门切房间”
  升级为连续走近、开门、穿越；再实现角色按 `traverse` 自主跨房间，而不是让
  共享 Cast 始终随玩家整体迁移。

### S2.3 `[NEXT]` 独立地点接入

接入庭院和"晓光忆时"作为独立地点，不直接替换客厅。

### S2.4 `[LATER]` 公共地点

增加街道、咖啡馆、公园等公共地点。

### S2.5 `[LATER]` 场景流送与离屏模拟

实现场景流送、远景代理、跨场景导航和角色离屏模拟。

## 建议执行顺序

住宅三房间、地点图、跨地点存档和可点击门基线已经建立；下一步补连续走廊、
玩家实体与角色自主跨房间，再建设庭院和街道，否则角色日程与离屏模拟会反复返工。

## 相关节点

- [T2 语义世界与空间协议](../T-runtime/T2-semantic-world.md) — 跨场景位置图与语义查询
- [C5 记忆、人格与日程](../C-characters/C5-memory-personality-schedule.md) — 日程需要跨场景日程
- [X1 存档和迁移](../X-engineering/X1-save-migration.md) — 存档需支持跨场景位置

> 相关文档：[S 分支总览](./README.md) · [分支依赖关系](../99-dependencies.md)
