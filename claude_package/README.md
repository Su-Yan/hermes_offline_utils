# Claude Code CLI Offline Deployment

Claude Code CLI (`@anthropic-ai/claude-code`) 离线构建与部署工具（结构与规范对齐 Hermes Agent & Codex CLI 离线部署体系）。

## 目录结构

所有下载的依赖与物料均保存在 `claude-agent/` 目录下，保持根目录整洁：

```
claude_package/
├── 00-install.sh            # 交互式菜单入口（构建/打包/安装/验证/检查）
├── 01-build-offline.ps1     # [步骤1] 外网下载依赖物料到 claude-agent/
├── 02-pack-offline.ps1      # [步骤2] 打包为 output/Claude-Code-FULL-Offline-*.zip
├── 03-install-offline.ps1   # [步骤3] 内网离线安装 Claude Code CLI
├── 04-verify-offline.ps1    # [步骤4] 离线环境验证
├── README.md                # 部署使用说明
├── claude-agent/            # 离线物料存放目录（整洁隔离）
│   ├── npm-cache/           # npm 完整离线依赖缓存
│   ├── npm-packages/        # @anthropic-ai/claude-code .tgz 安装包
│   ├── package.json         # 依赖声明
│   ├── package-lock.json    # 锁定版本
│   ├── VERSION.txt          # 版本号
│   ├── SHA256SUMS.txt       # 校验和
│   └── manifest.json        # 构建清单
└── output/                  # 离线 ZIP 输出目录
```

## 环境要求

- **操作系统**：Windows 10 / 11 x64（亦支持通过 bash 在 macOS / Linux 上执行）
- **Node.js**：`>= 18.0.0`（推荐 Node.js 18 LTS、20 LTS 或 22）
- **npm**：`>= 9.0.0`
- **PowerShell**：5.1 或 PowerShell 7+（Windows 默认自带）

---

## 使用流程

### 一、外网构建机

1. 进入 `claude_package` 目录，执行入口脚本：
   ```bash
   ./00-install.sh
   ```
   *（或直接在 PowerShell 中执行 `.\01-build-offline.ps1`）*

2. 选择 **[1] 外网构建机 - 构建 Claude Code Offline Bundle**
   - 自动获取最新 `@anthropic-ai/claude-code` 版本
   - 下载完整依赖缓存到 `claude-agent/npm-cache`
   - 生成离线安装包到 `claude-agent/npm-packages/*.tgz`
   - 自动运行真实离线测试 `npm ci --offline` 验证 100% 缓存完整性
   - 自动计算 SHA256 校验并生成 `manifest.json`

3. 选择 **[2] 外网构建机 - 打包 Offline ZIP**
   - 在 `output/` 目录下生成完整离线压缩包：  
     `Claude-Code-FULL-Offline-vx.x.x-win64.zip`

---

### 二、内网离线安装

1. 将 `output/` 中的 ZIP 包复制到内网机器并解压。
2. 进入解压后的目录，执行入口：
   ```bash
   ./00-install.sh
   ```
   *（或在 PowerShell 中执行 `.\03-install-offline.ps1` 或 `.\install-offline.ps1`）*

3. 选择 **[3] 内网机器 - 安装 Claude Code CLI**
   - 自动从本地 `claude-agent/npm-packages/*.tgz` 和 `claude-agent/npm-cache` 执行纯离线全局安装
   - 自动配置环境变量 `PATH`
   - 自动在当前目录生成 `claude.cmd` 快速启动器
   - 自动在桌面生成 `Claude Code` 快捷方式

4. 选择 **[4] 内网机器 - 验证离线环境**
   - 检查 Node.js、npm 以及 Claude Code CLI 命令可用性与版本

---

### 三、内网 API 与网关配置

在内网或离线环境中，Claude Code 通常连接内网私有模型代理网关（如 One API / LiteLLM / 自建反向代理），可通过环境变量配置：

#### PowerShell:
```powershell
# 配置内部代理网关地址
$env:ANTHROPIC_BASE_URL="http://your-internal-llm-proxy:8000/v1"

# 配置 API Key
$env:ANTHROPIC_API_KEY="sk-ant-your-key-here"

# 启动 Claude Code
claude
```

#### CMD / 批处理:
```cmd
set ANTHROPIC_BASE_URL=http://your-internal-llm-proxy:8000/v1
set ANTHROPIC_API_KEY=sk-ant-your-key-here
claude
```

#### Bash (Git Bash / Linux / macOS):
```bash
export ANTHROPIC_BASE_URL="http://your-internal-llm-proxy:8000/v1"
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
claude
```

---

## 离线安全原则

- **零外网依赖**：内网安装与验证阶段完全使用 `--offline` 选项，绝不尝试向公网发起请求。
- **校验可信**：包含 `SHA256SUMS.txt` 与 `manifest.json`，确保构建物料在内网流转过程未被篡改。
- **开箱即用**：提供快捷脚本、`claude.cmd` 启动器以及桌面快捷方式，方便在各种终端与权限环境下快速唤起。

