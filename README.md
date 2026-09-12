# hermes_offline_utils

> Windows 10 / 11 **完全离线部署** AI 工具的一键打包 & 安装工具集。
> 解决在**无法访问互联网的内网环境**中安装、运行 AI Agent 的难题。

---

## 概述

本仓库收录了两套结构对齐、风格统一的离线部署工具，分别针对：

| 工具包 | 目标软件 | 说明 |
|--------|----------|------|
| [`hermes_package/`](./hermes_package/) | [Hermes Agent](https://github.com/NousResearch/hermes-agent) | 完整 AI Agent + Desktop GUI 离线部署 |
| [`codex_package/`](./codex_package/) | [OpenAI Codex CLI](https://github.com/openai/codex) | Codex CLI 工具离线部署 |

两套工具均采用相同的「外网构建 → U 盘传输 → 内网安装」工作流。

---

## 工作流程

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│         外网 Windows 构建机      │      │         内网 Windows 目标机      │
│                                 │      │                                 │
│  sh 00-install.sh               │      │  sh 00-install.sh               │
│  ├─ [1] 构建 Offline Bundle     │      │  ├─ [3] 离线安装                │
│  └─ [2] 打包 ZIP                │─────▶│  └─ [4] 验证环境                │
│       output/*.zip              │      │                                 │
└─────────────────────────────────┘      └─────────────────────────────────┘
                              U盘 / 文件传输
```

---

## 快速开始

### 阶段一：外网构建（需要联网）

进入对应工具包目录，运行：

```bash
sh 00-install.sh
```

依次选择 **[1] 构建** → **[2] 打包**，完成后将 `output/` 下的 ZIP 文件复制到内网。

### 阶段二：内网安装（完全离线）

解压 ZIP，在解压目录运行：

```bash
sh 00-install.sh
```

选择 **[3] 安装**，完成后选 **[4] 验证**。

---

## 工具包详情

### 📦 hermes_package — Hermes Agent 离线部署

适用于需要在内网运行完整 Hermes Agent（含 Desktop 桌面应用）的场景。

**Bundle 包含内容：**

| 组件 | 说明 |
|------|------|
| Hermes Agent | 源码 + Python venv |
| Python 3.11 | 独立 runtime，无需系统 Python |
| Node.js | 独立 runtime |
| Git / Git Bash | Portable 版本 |
| agent-browser | 浏览器自动化工具 |
| Playwright Chromium | 离线浏览器内核 |
| ffmpeg | 音视频处理 |
| ripgrep | 高速文本搜索 |
| npm / Electron cache | 构建缓存 |
| Hermes Desktop | 编译好的 Windows 桌面应用 |

**外网构建机前置要求：**

| 工具 | 快速安装 |
|------|---------|
| [Git for Windows](https://git-scm.com/) | `winget install Git.Git` |
| [Node.js](https://nodejs.org/) 20 或 22 | `winget install OpenJS.NodeJS.LTS` |
| [ffmpeg](https://ffmpeg.org/) | `winget install Gyan.FFmpeg.Shared` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | `winget install BurntSushi.ripgrep.MSVC` |

> `uv` 由构建脚本自动安装，无需手动准备。

**安装后使用：**

```powershell
hermes --version
hermes doctor
hermes desktop --skip-build
```

---

### 📦 codex_package — Codex CLI 离线部署

适用于需要在内网使用 OpenAI Codex CLI 的场景（仅 npm 包，轻量）。

**Bundle 包含内容：**

| 组件 | 说明 |
|------|------|
| `@openai/codex` `.tgz` | npm 离线安装包 |
| npm-cache | 完整离线依赖缓存 |
| VERSION.txt | 版本号 |
| SHA256SUMS.txt | 校验和 |
| manifest.json | 构建清单 |

**外网构建机前置要求：**

- [Node.js](https://nodejs.org/) 20 或 22（含 npm）

**安装后使用：**

```powershell
codex --version
codex "请帮我写一个快速排序"
```

---

## 脚本说明

每个工具包内脚本结构相同：

| 脚本 | 场景 | 说明 |
|------|------|------|
| `00-install.sh` | 两端通用 | Git Bash 交互式菜单，统一入口 |
| `01-build-offline.ps1` | 外网构建机 | 下载全部依赖、构建 Bundle |
| `02-pack-offline.ps1` | 外网构建机 | 打包为离线 ZIP |
| `03-install-offline.ps1` | 内网目标机 | 完全离线安装 |
| `04-verify-offline.ps1` | 内网目标机 | 验证安装结果 |

---

## 注意事项

- ⚠️ **内网机器不要**手动运行 `npm install`、`pip install`、`git clone` 等联网命令，所有依赖应来自 Bundle。
- 🔄 安装完成后请**重新打开终端**，新的 PATH 才能生效。
- 📦 Bundle 中的启动器使用相对路径，解压到任意位置均可运行。
- 🖥️ 脚本需要在 **Git Bash**（Windows 上）中运行 `00-install.sh`，PowerShell 脚本由菜单自动调用。

---

## 目录结构

```
hermes_offline_utils/
├── hermes_package/             # Hermes Agent 离线部署工具
│   ├── 00-install.sh           # 交互式菜单入口
│   ├── 01-build-offline.ps1    # 外网：构建完整 Bundle
│   ├── 02-pack-offline.ps1     # 外网：打包 ZIP
│   ├── 03-install-offline.ps1  # 内网：安装
│   ├── 04-verify-offline.ps1   # 内网：验证
│   └── README.md
│
└── codex_package/              # Codex CLI 离线部署工具
    ├── 00-install.sh           # 交互式菜单入口
    ├── 01-build-offline.ps1    # 外网：下载 Codex 物料
    ├── 02-pack-offline.ps1     # 外网：打包 ZIP
    ├── 03-install-offline.ps1  # 内网：离线安装
    ├── 04-verify-offline.ps1   # 内网：验证
    └── README.md
```
