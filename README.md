# HermesOffline

Windows 10 / 11 离线部署 [Hermes Agent](https://github.com/NousResearch/hermes-agent) 的工具集。

---

## 工作流程

`
【外网构建机】                          【内网目标机】
  ① 运行 00-install.sh                   ③ 解压 ZIP
  ② 选 [1] 构建  →  _build/              ④ 运行 00-install.sh
     选 [2] 打包  →  output/*.zip  ──→      选 [3] 安装
                                            选 [4] 验证
`

### 阶段一：外网构建

在有互联网的 Windows 10/11 机器上运行：

`ash
sh 00-install.sh
`

选 **[1] 构建**，再选 **[2] 打包**，最终在 output/ 目录下得到：

`
output/
  Hermes-FULL-Offline-<commit>-win64.zip
`

将该 ZIP 通过 U 盘等方式传入内网。

### 阶段二：内网安装

在内网 Windows 10/11 机器上解压 ZIP，然后运行：

`ash
sh 00-install.sh
`

选 **[3] 安装**，安装完毕后选 **[4] 验证**。

---

## 脚本说明

| 脚本 | 适用机器 | 说明 |
|------|---------|------|
| `00-install.sh` | 两端 | Git Bash 交互式菜单，统一入口 |
| `01-build-offline.ps1` | 外网构建机 | 拉取源码、安装所有依赖、构建 Desktop |
| `02-pack-offline.ps1` | 外网构建机 | 打包为 ZIP，生成内网安装/验证脚本 |
| `03-install-offline.ps1` | 内网目标机 | 调用 Bundle 内的 install-offline.ps1 |
| `04-verify-offline.ps1` | 内网目标机 | 调用 Bundle 内的 verify-offline.ps1 |

---

## 目录结构

`
HermesOffline/
├── 00-install.sh              # 交互式菜单（Git Bash）
├── 01-build-offline.ps1       # 外网：构建 Bundle
├── 02-pack-offline.ps1        # 外网：打包 ZIP
├── 03-install-offline.ps1     # 内网：安装
├── 04-verify-offline.ps1      # 内网：验证
├── README.md
├── .gitignore
│
├── hermes-agent/              # Hermes Agent 本地仓库（可选，加速构建）
│   └── hermesofflinewheels/   # 构建后端所需 wheel
│
├── wheels/                    # 预下载的 Python 依赖 wheel（131 个）
│
├── _build/                    # 构建产物（自动生成，不提交）
│   └── Hermes-Offline-Bundle/ # Bundle 内容
│
└── output/                    # 打包产物（自动生成，不提交）
    └── Hermes-FULL-Offline-*.zip
`

---

## 前置要求（外网构建机）

| 工具 | 版本要求 | 安装建议 |
|------|---------|---------|
| Git for Windows | 任意 | winget install Git.Git |
| Node.js | 20 或 22 | winget install OpenJS.NodeJS.LTS |
| ffmpeg | 任意 | winget install Gyan.FFmpeg.Shared |
| ripgrep | 任意 | winget install BurntSushi.ripgrep.MSVC |

> **uv** 会由 01-build-offline.ps1 自动安装，无需手动准备。

---

## Bundle 内容（打包后）

安装包包含以下完整离线组件，内网机器无需访问互联网：

- Hermes Agent（源码 + Python venv）
- Python 3.11 runtime
- Node.js runtime
- Portable Git / Git Bash
- agent-browser + Playwright Chromium
- ffmpeg
- ripgrep
- Electron cache / electron-builder cache
- npm cache
- Hermes Desktop（编译好的 Windows 安装包）

---

## 内网安装后的使用

安装完成后桌面会出现两个快捷方式：

- **Hermes Desktop** — 启动图形界面
- **Hermes CLI** — 打开 PowerShell 命令行

也可以直接在任意终端使用（重新打开终端后生效）：

`powershell
hermes --version
hermes doctor
hermes desktop --skip-build
`

---

## 注意事项

- 内网机器**不要**手动运行 npm install、pip install、npx playwright install、git clone 等命令，所有依赖应来自 Bundle。
- 安装后请**重新打开终端**，新的 PATH 才能生效。
- Bundle 中的启动器（hermes.cmd）使用相对路径，解压后无需修改即可运行。
