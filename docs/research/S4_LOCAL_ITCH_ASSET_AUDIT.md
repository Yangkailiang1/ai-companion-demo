# S4 本地 itch.io 资产审计

> 审计日期：2026-07-28
> 输入目录：`/Users/yangkailiang/Documents/ai_games/model/物体`
> 目标：判断本地下载包能否进入公开仓库的参数化 Asset Registry。

## 结论

| 资产包 | 技术内容 | 公共仓库结论 |
|---|---|---|
| 7 个 KayKit Bits 包 | 均含 GLTF、FBX、OBJ；ZIP 安全审计通过 | `ACCEPT`：官方页面标记 CC0；逐批提取，不整包导入 |
| KayKit Furniture Bits | 53 GLTF、106 FBX、53 OBJ | `ACCEPT`：首批扶手椅、沙发、落地灯已完成 Godot 预览 |
| UiCozyFree | PNG UI 素材，无 3D 模型 | `REJECT_3D`：可在未来 UI 素材流程单独审计 |
| Modular Roads - Base | GLB、FBX、OBJ、Blend | `REJECT_PUBLIC`：条款要求署名且不允许重新分发 |
| Modular Village Collection | OBJ | `QUARANTINE`：未在压缩包内发现清晰许可，公开再分发权不明确 |

## KayKit 可用范围

本地 KayKit Board Game、City Builder、Forest Nature、Furniture、Halloween、
Resource、Restaurant 共七个包均通过以下安全门：

- 无路径穿越、符号链接、可执行文件和嵌套压缩包；
- 存在 Godot 可直接导入的 GLTF，且贴图/二进制依赖完整；
- 官方资产页明确为 CC0，可商用且无需署名；
- 导入项目时仍须保存官方页面、访问日期、源包 SHA-256 和逐文件哈希。

首批使用 `KayKit_Furniture_Bits_1.0_FREE.zip`，源包 SHA-256：

`e6d75f34c5545486b5a8f45f86209dbd49092f3e77ae23011bdb87edab89e7e4`

已预览资产：

| asset_id | 原生 AABB（米） | 轴向 | 三角面 |
|---|---:|---|---:|
| `kaykit_armchair_pillows` | 1.8000 × 1.2241 × 1.6000 | front `+Z`, up `+Y` | 614 |
| `kaykit_couch_pillows` | 3.0000 × 1.2241 × 1.6000 | front `+Z`, up `+Y` | 808 |
| `kaykit_lamp_standing` | 1.0000 × 2.5200 × 1.0000 | front `+Z`, up `+Y` | 320 |

这三件资产目前仅具备 `observable + static` 候选能力。加入碰撞、座位锚点、
灯光状态或角色交互后，必须再走 S3/T2 的交互物体验收，不得因为视觉模型存在而
自动宣称为可交互对象。

## 网络来源实测

- Poly Haven：官方 Files API 与 GLTF 小文件下载通过；
- ambientCG：官方 API 与模型 ZIP 下载通过，但查询结果必须再次验证 `dataType`；
- Kenney：Furniture Kit ZIP 下载与完整性检查通过，直链可能变化；
- Quaternius / itch.io：官方页面许可可审计，但下载组件可能要求浏览器会话，
  不绕过访问控制，改为接受用户手动下载的压缩包。

下载批处理必须使用 `$download-open-3d-assets`；规范化与 Godot 预览必须使用
`$build-parametric-asset-library`。每批最多三个同风格、同 archetype 资产，
Codex 保留许可接受、视觉验收和提交权限。
