# Codex CLI Offline Deployment

Codex CLI 离线构建与部署工具（结构与规范对齐 Hermes Agent 离线部署体系）。

## 目录结构

所有下载的物料均保存在 `codex-agent/` 目录下，保持主目录整洁：

```
codex_package/
├── 00-install.sh            # 交互式菜单入口（构建/打包/安装/验证/检查）
├── 01-build-offline.ps1     # [步骤1] 外网下载依赖物料到 codex-agent/
├── 02-pack-offline.ps1      # [步骤2] 打包为 output/Codex-FULL-Offline-*.zip
├── 03-install-offline.ps1   # [步骤3] 内网离线安装 Codex CLI
├── 04-verify-offline.ps1    # [步骤4] 离线环境验证
├── README.md                # 部署使用说明
├── codex-agent/             # 离线物料存放目录（整洁隔离）
│   ├── npm-cache/           # npm 完整离线依赖缓存
│   ├── npm-packages/        # @openai/codex .tgz 安装包
│   ├── package.json         # 依赖声明
│   ├── package-lock.json    # 锁定版本
│   ├── VERSION.txt          # 版本号
│   ├── SHA256SUMS.txt       # 校验和
│   └── manifest.json        # 构建清单
└── output/                  # 离线 ZIP 输出目录
```

## 使用流程

### 一、外网构建机

1. 执行入口脚本：
   ```bash
   ./00-install.sh
   ```
2. 选择 **[1] 外网构建机 - 构建 Codex Offline Bundle**
   - 自动下载最新 Codex CLI、完整依赖缓存到 `codex-agent/`
   - 自动运行真实离线测试 `npm ci --offline` 验证完整性
3. 选择 **[2] 外网构建机 - 打包 Offline ZIP**
   - 在 `output/` 目录下生成完整离线压缩包 `Codex-FULL-Offline-vx.x.x-win64.zip`

---

### 二、内网离线安装

1. 将 `output/` 中的 ZIP 包复制到内网机器并解压。
2. 进入解压后的目录，执行：
   ```bash
   ./00-install.sh
   ```
3. 选择 **[3] 内网 Windows - 安装 Codex CLI**
   - 自动从本地 `codex-agent/npm-packages/*.tgz` 和 `codex-agent/npm-cache` 离线全局安装
4. 选择 **[4] 内网 Windows - 验证离线环境**
   - 检查 Node.js、npm 以及 Codex 命令可用性
