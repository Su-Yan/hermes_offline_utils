# HermesOffline

> Windows 10 / 11 离线部署 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 的一键打包 & 安装工具。

---

## 工作流程

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│         外网构建机               │      │         内网目标机               │
│                                 │      │                                 │
│  sh 00-install.sh               │      │  sh 00-install.sh               │
│  ├─ [1] 构建 Bundle             │      │  ├─ [3] 安装                    │
│  └─ [2] 打包 ZIP                │─────▶│  └─ [4] 验证                    │
│       output/*.zip              │      │                                 │
└─────────────────────────────────┘      └─────────────────────────────────┘
```

---

## 快速开始

### 阶段一：外网构建（需要联网）

```bash
sh 00-install.sh
```

按 **[1] 构建**，再按 **[2] 打包**，完成后将 `output/` 下的 ZIP 文件复制到内网。

```
output/
  Hermes-FULL-Offline-<commit>-win64.zip   ← 通过 U 盘等方式传入内网
```

### 阶段二：内网安装（完全离线）

解压 ZIP，进入解压目录，运行：

```bash
sh 00-install.sh
```

按 **[3] 安装**，完成后按 **[4] 验证**。

---

## 脚本说明

| 脚本 | 场景 | 说明 |
|------|------|------|
| `00-install.sh` | 两端通用 | Git Bash 交互式菜单，统一入口 |
| `01-build-offline.ps1` | 外网构建机 | 克隆源码、安装全部依赖、构建 Desktop |
| `02-pack-offline.ps1` | 外网构建机 | 打包为 ZIP，生成内网安装 & 验证脚本 |
| `03-install-offline.ps1` | 内网目标机 | 调用 Bundle 内的 `install-offline.ps1` |
| `04-verify-offline.ps1` | 内网目标机 | 调用 Bundle 内的 `verify-offline.ps1` |

---

## 前置要求（仅外网构建机）

| 工具 | 版本 | 快速安装 |
|------|------|---------|
| [Git for Windows](https://git-scm.com/) | 任意 | `winget install Git.Git` |
| [Node.js](https://nodejs.org/) | 20 或 22 | `winget install OpenJS.NodeJS.LTS` |
| [ffmpeg](https://ffmpeg.org/) | 任意 | `winget install Gyan.FFmpeg.Shared` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | 任意 | `winget install BurntSushi.ripgrep.MSVC` |

> `uv` 由 `01-build-offline.ps1` 自动安装，无需手动准备。

---

## Bundle 内容

打包后的 ZIP 包含以下完整离线组件，内网机器无需访问互联网：

| 组件 | 说明 |
|------|------|
| Hermes Agent | 源码 + Python venv |
| Python 3.11 | 独立 runtime |
| Node.js | 独立 runtime |
| Git / Git Bash | Portable 版本 |
| agent-browser | 浏览器自动化工具 |
| Playwright Chromium | 离线浏览器内核 |
| ffmpeg | 音视频处理 |
| ripgrep | 高速文本搜索 |
| npm / Electron cache | 构建缓存 |
| Hermes Desktop | 编译好的 Windows 桌面应用 |

---

## 安装后使用

安装完成后桌面会出现两个快捷方式：

- 🖥️ **Hermes Desktop** — 启动图形界面
- ⌨️ **Hermes CLI** — 打开 PowerShell 命令行

重新打开终端后也可直接使用命令行：

```powershell
hermes --version
hermes doctor
hermes desktop --skip-build
```

---

## 目录结构

```
HermesOffline/
├── 00-install.sh              # 交互式菜单（Git Bash）
├── 01-build-offline.ps1       # 外网：构建 Bundle
├── 02-pack-offline.ps1        # 外网：打包 ZIP
├── 03-install-offline.ps1     # 内网：安装
├── 04-verify-offline.ps1      # 内网：验证
├── README.md
├── .gitignore
├── .gitattributes
│
├── hermes-agent/              # (可选) 本地源码，加速构建，不提交
├── wheels/                    # (可选) 预下载 wheel，不提交
│
├── _build/                    # 构建产物，自动生成，不提交
└── output/                    # ZIP 打包产物，自动生成，不提交
```

---

## 注意事项

- ⚠️ 内网机器**不要**手动运行 `npm install`、`pip install`、`npx playwright install`、`git clone` 等命令，所有依赖应来自 Bundle。
- 🔄 安装后请**重新打开终端**，新的 PATH 才能生效。
- 📦 Bundle 中的启动器使用相对路径（`%~dp0`），解压到任意位置均可运行。