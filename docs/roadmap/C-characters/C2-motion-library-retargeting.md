# C2. 动作库与骨骼重定向

> 所属分支：C. AI 角色
> 节点编号：C2
> 状态：`[ACTIVE]`
> 依赖：C1（动作路由）、T1（PerformanceIntent）
> 最后更新：2026-07-28 | 基线程：v0.8.7

## 当前状态

- 企鹅有已烘焙动作；诀使用轻量骨骼覆盖和程序化兜底。
- HumanML3D/Light-T2M 已建立离线包和 22 关节映射，但真实批量样本仍待服务器生成与验收。
- 三名本机 MMD Q 角色已验证日文骨骼到语义骨骼映射，以及
  `idle/wave/nod/think/happy/talk` Overlay；下一步仍需烘焙真实 VMD/动作库剪辑。
- `[DONE baseline]` 三名 MMD Q 角色新增循环 `walk` 骨骼层：导航负责根节点位移，
  手臂、腿和髋部在行走期间循环摆动，到达后由 `idle` 提示可靠停止。
- `[DONE H10-B4]` 程序化步态改为按实际水平位移（米）推进相位；堵塞时不再原地
  空走，并通过起停混合回到基准姿势。诀补齐左右大腿、小腿和脚的语义骨骼链，
  三名 Q 角色分别使用柔和、轻快和克制的步幅参数。
- `[DONE H10-B4]` 企鹅原生 `walk` 剪辑按实际速度在安全范围内调节播放速率；
  所有动作仍为 in-place，世界位移只由 AgentBase/NavigationAgent3D 管理。
- 当前 HumanML3D 本地目录只有 `Mean.npy/Std.npy` 统计量，没有可重定向的真实动作
  样本；因此不能将程序化 Overlay 描述为已经接入 HumanML3D 动作剪辑。
- `[DONE batch skill baseline]` `$prepare-motion-library-assets` 已把 NPY、BVH、
  body VMD、FBX/GLB 动画的许可审计、角色无关规范化、目标骨架重定向、烘焙和
  视觉验收拆开；DeepSeek 每批最多准备五条同源动作候选。

## 规划节点

### C2.1 `[ACTIVE locomotion baseline]` 核心动作库

建立 20-30 个核心动作：自然待机、行走、转身、挥手、点头、坐下、拿取、放下、喝、读、指向等。

### C2.2 `[NEXT]` 诀的动画重定向

完成诀的 Blender 重定向与烘焙动画，替代程序化上臂动作。

### C2.3 `[ACTIVE locomotion profile]` 统一动作元数据

建立统一动作元数据：循环、root motion、占用身体层、目标、接触事件和适用骨架。

- `[DONE H10-B4]` `locomotion_profile` 已统一米制参考速度、步幅、起停混合、
  播放速率上下限和 `in_place` root-motion 策略。
- `[NEXT]` 将身体层占用、接触事件和适用骨架扩展到全部核心动作。

### C2.4 `[ACTIVE gait baseline]` 动作质量提升

足锁、手部接触、关节限幅、穿模检测和循环过渡。

- `[DONE H10-B4 baseline]` 步态具备位移同步、堵塞冻结、膝/脚单侧抬升和起停混合。
- `[NEXT]` 为烘焙剪辑增加足锁、地面接触事件、关节限幅和跨动作 BlendTree。

### C2.5 `[RESEARCH]` Light-T2M 生成管

Light-T2M 生成候选动作，离线筛选后进入正式动作库；不直接控制碰撞关键行为。

### C2.6 `[DONE tooling contract]` 动作资产批处理合同

共享动作库只保存语义动作元数据和角色无关 Motion Package；每个角色只通过
版本化 bone map、rest-pose correction 和 `clip_map` 接入烘焙剪辑。动作批处理
不得修改人物网格、表情映射、场景或 LLM。

## 后续任务记录

- [ ] 用真实 HumanML3D/Light-T2M `.npy` 替换 smoke fixture，生成 5-10 个语义明确的动作包
- [ ] 增强 `tools/blender/bake_retarget_package.py`：目标骨骼 rest-pose 对齐、关节限幅、足锁、root motion 选择
- [ ] 建立动作验收清单：骨骼长度误差、脚滑、朝向、穿模、循环衔接、表情搭配
- [ ] 将通过验收的动作加入 `data/motion_catalog.json` 与 `PerformanceCueTypes`
- [ ] 后续若切换角色/动作模型，只新增对应 bone map 与 baker adapter，不改 Godot Runtime 主链路

## 相关节点

- [C1 文本到动作/表情路由](./C1-text-to-action-routing.md) — 动作的路由和选择
- [C4 角色与场景交互](./C4-character-scene-interaction.md) — 交互时需要的动作支撑
- [C3 表情和身体语言](./C3-expression-body-language.md) — 动作与表情的协同

> 相关文档：[C 分支总览](./README.md)
