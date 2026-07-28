# Claude Code / DeepSeek 开发交接包

> 项目：AI Living Town / AI Companion Demo
> 基线：Godot 4.6.1，项目版本 v0.8.8
> 生成日期：2026-07-28

本目录把长期规划树拆成六条可以独立推进的开发方向。每份任务都包含功能范围、
文件所有权、禁止事项、失败路径和验收命令，可直接交给 Claude Code、DeepSeek
或其他代码 Agent。

## 文档索引

| 编号 | 开发方向 | 路线图 | 推荐优先级 | 主要产物 |
|---|---|---|---|---|
| H10 | [物理交互与动态导航](./10-physical-interaction-navigation.md) | C4、S3、T2 | P0 | NavMesh avoidance、交互锚点、占用锁、拿取闭环 |
| H20 | [动作库、表情与角色适配](./20-motion-expression-adapters.md) | C1、C2、C3、C6 | P0 | 核心动作元数据、重定向、表情覆盖率、路由测试 |
| H30 | [AI 剧情导演与演出工具](./30-ai-story-directing.md) | D2、D3、D4 | P1 | 并行 Beat、同步点、预览确认、语音/镜头调度 |
| H40 | [自主生活、记忆与社交](./40-autonomous-life-social.md) | C5、C9、X1 | P0 | 共同活动、行为连续性、关系图、五分钟生活验收 |
| H50 | [UI、镜头与玩家体验](./50-ui-player-experience.md) | S1、P2、P3 | P1 | 响应式 UI、目标选择、玩家模式与交互射线 |
| H60 | [开源 Runtime 与质量工程](./60-open-source-runtime-quality.md) | T3、O1、O4、X2 | P0 | 插件边界、公开检出测试、CI、许可证与贡献模板 |

## 推荐并行方式

- 第一批可以并行：H20、H30、H50、H60。
- H10 与 H40 可以并行，但 H10 独占物理执行和导航文件，H40 不得修改这些文件。
- H30 只拥有导演层，不得顺手修改认知、动作执行器或 UI。
- H50 只拥有 UI、相机和玩家控制，不修改角色自主决策。
- 合并顺序建议：H60 → H20 → H10 → H40 → H30 → H50；每次合并后运行公共回归。

## 使用方式

1. 先让执行 Agent 完整阅读 [通用执行规范](./00-execution-guide.md)。
2. 每次只交付一份 H10-H60 文档，不要一次要求一个 Agent 实现全部方向。
3. 为每条任务创建独立 Git 分支或独立 worktree。
4. 执行 Agent 不负责推送 `master`；由项目所有者或主控 Agent 验收后合并。

Claude Code 示例：

```bash
nvm use 22
claude -p --permission-mode acceptEdits \
  --allowedTools Read Edit Write Glob Grep Bash \
  < docs/handoffs/10-physical-interaction-navigation.md
```

DeepSeek 应将 `00-execution-guide.md` 与目标任务文档一起放入上下文，并明确要求：
“直接检查、编辑、运行测试，不要只给方案；测试失败不得宣称完成”。

## 公共完成条件

任何任务只有同时满足以下条件才算可交付：

- 正常路径、失败路径、降级路径均有自动化测试；
- `git diff --check` 通过；
- 没有读取、打印或提交密钥；
- 没有提交 `assets/local_characters/` 或许可证不明资产；
- 相关路线图和架构文档已更新；
- 报告包含实际运行的命令、退出码和未解决限制；
- 用户可见改动包含 1280×720 与 2560×1440 的视觉验收。
