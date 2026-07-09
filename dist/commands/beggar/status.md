---
name: BEGGAR: Status
description: "查看当前 beggar 配置、OpenSpec 变更进度和 RTK token 节省统计"
---

查看 beggar 当前状态。

执行以下诊断命令并汇总输出：

**1. Agent 模型配置**
```bash
beggar show 2>/dev/null || echo "[beggar] setup.sh 未找到"
```

**2. RTK Token 节省统计**
```bash
rtk gain 2>/dev/null || echo "[beggar] RTK 未安装或无可用的 gain 数据"
```

**3. 活跃 OpenSpec 变更**
```bash
openspec list --json 2>/dev/null || echo "[beggar] 无活跃变更或 openspec 未安装"
```

**4. 最近 git 提交**
```bash
git log --oneline -5 2>/dev/null || echo "[beggar] 非 git 仓库"
```

将以上输出整理为表格或结构化报告，包含：
- 当前预设和 agent 模型配置
- RTK 节省统计（如有）
- 活跃变更列表和进度
- 下一步建议
