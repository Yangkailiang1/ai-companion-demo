# O2/C2/C3/C6 — 压缩资产元数据合同测试

只修改 `tools/assets/test_asset_metadata_contracts.py`。

当前 15 项测试全部通过，但文件 394 行，违反 `CLAUDE.md` 中测试文件 250 行硬上限。
将重复角色用例改成参数表 + `subTest`，目标不超过 220 行。

必须保持以下覆盖：

- 企鹅 unknown/local_only/no your-org；
- 三角色 unique morph 69/37/70，缺失本地角色时 skip；
- 三角色 expression candidate status、runtime non-regression，缺失时 skip；
- smoke_walk fixture 与 pipeline_smoke_test；
- Poly Haven 所有路径 `res://`；
- 厨房三候选 previewed、AABB 正数、source SHA 非空。

约束：

- 标准库 unittest，无新依赖；
- 不降低断言强度，不修改被测文件；
- 文件和函数保留 Roadmap、职责、副作用注释；
- 不提交 Git。

验收：

```bash
wc -l tools/assets/test_asset_metadata_contracts.py
python3 -m py_compile tools/assets/test_asset_metadata_contracts.py
python3 -m unittest tools.assets.test_asset_metadata_contracts -v
git diff --check
```
