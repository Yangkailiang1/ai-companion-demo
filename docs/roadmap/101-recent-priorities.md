# 最近三个版本的推荐优先级

> 所属文档：AI Living Town 开发规划树
> 最后更新：2026-07-28 | 当前切片：v0.8.9

## v0.6（稳定客厅生活）

1. `[DONE] X1` 最小存档协议，保存角色和物体状态。
2. `[DONE] T2.1 + S3.1` 盆栽状态机，作为通用可交互物体模板。
3. `[DONE baseline] C4.0 + C5.0` 环境驱动的浇水、休息、观察记忆和玩家抢占。
4. `T1.1 + C1.1` 统一表现意图和动作路由诊断日志。
5. `S1.1–S1.3` UI 消息气泡、目标角色选择和分辨率适配。

## v0.7（具身生活感）

1. `[ACTIVE baseline] C9.1–C9.4` Utility AI、微行为、日程差异、行为过渡与任务恢复。
2. `C9.5 + C4` 用浇水打通真实拿取、携带、使用、反馈和归位闭环。
3. `[ACTIVE local baseline] C2 + C3` 三名 MMD Q 角色已有循环行走和模型原生
   惊讶/难过/害羞等 Morph；继续完成自然待机、注视、转身和真实动画重定向。
4. `C9.6 + C5` 实现双角色共同看电视的第一个共同活动。

## v0.8（Q版角色小剧场）← 当前

1. `[DONE MVP] D1` JSON 小剧本、白名单校验、角色绑定和聊天命令。
2. `[ACTIVE baseline] D2` 双角色走位、注视、动作、表情、对白、取消和记忆。
3. `[DONE MVP] D3 + C9` 自由/演出双模式，自然语言剧本由 LLM 动态编排。
4. `[DONE local catalog] C6 + C8 + O4` 三名 PMX Q 角色完成 GLB 转换、
   MMD 材质/Morph 映射、点名路由、剧本 cast、独立记忆和开源许可隔离；
   正式可再分发角色资产仍待补充。
5. `[DONE physics baseline] C4.4 + S3` 角色、房间与主要家具已有碰撞体；
   书和奶茶支持真实拿取/放下/投掷，茶几、书架、壁灯可由 LLM 语义动作驱动。
6. `C5 + C9.6` 打磨邀请看电视等共同活动，使剧情结束后自然回到生活。
7. `[DONE H10-B3] C4.5` 动作失败停止队列、释放占用和自主活动资源，不再伪成功。
8. `[DONE H10-B5 baseline] S3.7 + T2` 黄金对象与 Skill 已完成首批批量接入：
   `wall_art`、`window`、`back_wall_shelf`、`leaf_art` 均具备碰撞、锚点、
   SemanticWorld 描述和自动验收；下一步扩展 portable/stateful/container/seat。
9. `[ACTIVE design baseline] S4.0` 参数化场景采用 Scene Recipe、Asset Registry、
   Semantic/Interaction Layer 三层合同；下一步先生成与现有客厅等价的 Preview，
   通过回归和视觉验收后再替换主场景。

## v0.9（从客厅到住宅）

1. `S2` 住宅多房间和跨场景导航。
2. `P2 + P3` 玩家控制器与场景交互。
3. `D2` 镜头、并行 Beat、语音同步和日程恢复。

---

> 相关文档：[建议版本切片](./100-version-slices.md) · [总规划树](./README.md)
