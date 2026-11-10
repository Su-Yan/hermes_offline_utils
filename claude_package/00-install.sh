#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# UTF-8
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

pause_screen() {
    echo
    read -r -p "按 Enter 返回菜单..."
}

find_powershell() {
    if command -v pwsh >/dev/null 2>&1; then
        echo "pwsh"
    elif command -v powershell.exe >/dev/null 2>&1; then
        echo "powershell.exe"
    elif command -v powershell >/dev/null 2>&1; then
        echo "powershell"
    else
        echo ""
    fi
}

run_ps1() {
    local script="$1"
    local full_path="$SCRIPT_DIR/$script"

    if [[ ! -f "$full_path" ]]; then
        echo
        echo -e "${RED}[错误] 找不到 $script${RESET}"
        pause_screen
        return 1
    fi

    local ps
    ps=$(find_powershell)

    if [[ -z "$ps" ]]; then
        echo
        echo -e "${RED}[错误] 未检测到 PowerShell 环境。${RESET}"
        pause_screen
        return 1
    fi

    echo
    echo -e "${CYAN}执行：$script ($ps)${RESET}"
    echo

    "$ps" \
        -NoProfile \
        -ExecutionPolicy Bypass \
        -File "$full_path"

    local rc=$?

    echo

    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}[失败] $script 返回代码：$rc${RESET}"
        pause_screen
        return $rc
    fi

    echo -e "${GREEN}[完成] $script 执行成功${RESET}"
    pause_screen

    return 0
}

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------

show_header() {
    clear

    echo
    echo "============================================================"
    echo
    echo "          Claude Code CLI 离线部署工具"
    echo
    echo "============================================================"
    echo
    echo "当前目录："
    echo "  $SCRIPT_DIR"
    echo
}

# ------------------------------------------------------------
# 1. Build
# ------------------------------------------------------------

build_bundle() {
    clear

    echo
    echo "============================================================"
    echo "  1. 构建 Claude Code FULL Offline Bundle"
    echo "============================================================"
    echo
    echo "适用于：外网构建机 (Windows / Linux / macOS)"
    echo
    echo "将准备（下载并保存到 claude-agent 目录）："
    echo "  - 获取最新 Claude Code (@anthropic-ai/claude-code) 版本"
    echo "  - 下载完整 npm 离线缓存 (npm-cache)"
    echo "  - 生成 Claude Code npm 离线安装包 (npm-packages/*.tgz)"
    echo "  - 执行真实离线安装测试 (npm ci --offline)"
    echo "  - 生成 SHA256 校验与 manifest.json"
    echo
    echo -e "${YELLOW}注意：该步骤需要访问互联网。${RESET}"
    echo

    read -r -p "确认开始构建？[y/N] " answer

    case "$answer" in
        y|Y)
            run_ps1 "01-build-offline.ps1"
            ;;
        *)
            echo "已取消。"
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------
# 2. Pack
# ------------------------------------------------------------

pack_bundle() {
    clear

    echo
    echo "============================================================"
    echo "  2. 打包 Claude Code FULL Offline Bundle"
    echo "============================================================"
    echo

    if [[ ! -d "_build/Claude-Offline-Bundle" && ! -d "claude-agent" ]]; then
        echo -e "${RED}[错误] 找不到构建产物：_build/Claude-Offline-Bundle 或 claude-agent${RESET}"
        echo
        echo "请先执行 [1] 构建。"
        pause_screen
        return
    fi

    read -r -p "确认开始打包离线 ZIP？[y/N] " answer

    case "$answer" in
        y|Y)
            run_ps1 "02-pack-offline.ps1"
            ;;
        *)
            echo "已取消。"
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------
# 3. Install
# ------------------------------------------------------------

install_bundle() {
    clear

    echo
    echo "============================================================"
    echo "  3. 安装 Claude Code CLI (离线模式)"
    echo "============================================================"
    echo
    echo "适用于：内网 / 离线环境"
    echo
    echo "本步骤不访问互联网，完全从本地 claude-agent/npm-packages 离线安装。"
    echo

    read -r -p "确认开始离线安装？[y/N] " answer

    case "$answer" in
        y|Y)
            local ps
            ps=$(find_powershell)
            if [[ -n "$ps" ]]; then
                run_ps1 "03-install-offline.ps1"
            else
                echo -e "${YELLOW}未检测到 PowerShell，使用 Bash 进行离线安装...${RESET}"
                local agent_dir="$SCRIPT_DIR/claude-agent"
                [[ ! -d "$agent_dir" ]] && agent_dir="$(dirname "$SCRIPT_DIR")/claude-agent"
                [[ ! -d "$agent_dir" ]] && agent_dir="$SCRIPT_DIR"

                local cache_dir="$agent_dir/npm-cache"
                local pkg_dir="$agent_dir/npm-packages"
                local tgz
                tgz=$(find "$pkg_dir" -maxdepth 1 -name "*.tgz" 2>/dev/null | head -n 1)

                if [[ -z "$tgz" ]]; then
                    echo -e "${RED}[错误] 未在 $pkg_dir 找到 .tgz 安装包${RESET}"
                    pause_screen
                    return 1
                fi

                echo -e "${CYAN}正在离线全局安装: $tgz${RESET}"
                npm install -g "$tgz" --cache "$cache_dir" --offline --prefer-offline --no-audit --no-fund
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}[成功] Claude Code 离线安装成功！${RESET}"
                    claude --version 2>/dev/null || true
                else
                    echo -e "${RED}[失败] 安装过程中出现错误${RESET}"
                fi
                pause_screen
            fi
            ;;
        *)
            echo "已取消。"
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------
# 4. Verify
# ------------------------------------------------------------

verify_bundle() {
    clear

    echo
    echo "============================================================"
    echo "  4. 验证 Claude Code 离线环境"
    echo "============================================================"
    echo
    echo "将检查："
    echo "  [1] Node.js (要求 >= 18.0.0)"
    echo "  [2] npm"
    echo "  [3] Claude Code CLI 命令与版本"
    echo

    local ps
    ps=$(find_powershell)
    if [[ -n "$ps" ]]; then
        run_ps1 "04-verify-offline.ps1"
    else
        echo -e "${YELLOW}未检测到 PowerShell，使用 Bash 进行环境验证...${RESET}"
        local pass=0
        local fail=0

        echo -n "[1] Node.js: "
        if command -v node >/dev/null 2>&1; then
            local nver
            nver=$(node -v)
            echo -e "${GREEN}$nver${RESET}"
            local major
            major=$(echo "$nver" | sed 's/^v//' | cut -d. -f1)
            if [[ "$major" -lt 18 ]]; then
                echo -e "    ${YELLOW}[警告] Claude Code 推荐 Node.js >= 18.0.0，当前版本较低${RESET}"
            fi
            pass=$((pass+1))
        else
            echo -e "${RED}未安装 (必须)${RESET}"
            fail=$((fail+1))
        fi

        echo -n "[2] npm: "
        if command -v npm >/dev/null 2>&1; then
            echo -e "${GREEN}$(npm -v)${RESET}"
            pass=$((pass+1))
        else
            echo -e "${RED}未安装 (必须)${RESET}"
            fail=$((fail+1))
        fi

        echo -n "[3] Claude Code CLI: "
        if command -v claude >/dev/null 2>&1; then
            local cver
            cver=$(claude --version 2>/dev/null || echo "已安装")
            echo -e "${GREEN}$cver${RESET}"
            pass=$((pass+1))
        else
            echo -e "${RED}未找到 claude 命令${RESET}"
            fail=$((fail+1))
        fi

        echo
        echo "============================================================"
        if [[ $fail -eq 0 ]]; then
            echo -e "${GREEN} 验证通过 (VERIFICATION SUCCESS)${RESET}"
        else
            echo -e "${RED} 验证失败: $fail 项异常${RESET}"
        fi
        echo "============================================================"
        pause_screen
    fi
}

# ------------------------------------------------------------
# 5. Files
# ------------------------------------------------------------

show_files() {
    clear

    echo
    echo "============================================================"
    echo "  当前目录文件与物料"
    echo "============================================================"
    echo
    echo "PowerShell 脚本："
    find . -maxdepth 1 -type f -name "*.ps1" -printf "  %f\n" 2>/dev/null || ls *.ps1 2>/dev/null

    echo
    echo "Shell 脚本："
    find . -maxdepth 1 -type f -name "*.sh" -printf "  %f\n" 2>/dev/null || ls *.sh 2>/dev/null

    echo
    echo "物料目录 (claude-agent)："
    if [[ -d "claude-agent" ]]; then
        echo "  [存在] claude-agent/"
        ls -la "claude-agent" 2>/dev/null | head -15
    else
        echo "  [不存在] 请先执行 [1] 构建"
    fi

    echo
    echo "构建临时目录 (_build)："
    if [[ -d "_build" ]]; then
        echo "  [存在] _build/"
    else
        echo "  [不存在]"
    fi

    echo
    echo "输出目录 (output)："
    if [[ -d "output" ]]; then
        find "output" -maxdepth 1 -type f -printf "  %f\n" 2>/dev/null || ls output 2>/dev/null
    else
        echo "  [不存在]"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 6. PowerShell / Environment Check
# ------------------------------------------------------------

powershell_check() {
    clear

    echo
    echo "============================================================"
    echo "  系统与运行环境检查"
    echo "============================================================"
    echo

    local ps
    ps=$(find_powershell)

    echo -n "PowerShell: "
    if [[ -n "$ps" ]]; then
        echo -e "${GREEN}$ps${RESET}"
    else
        echo -e "${YELLOW}未找到 (Windows 默认自带，Linux/macOS 可选安装 pwsh)${RESET}"
    fi

    echo -n "Node.js: "
    if command -v node >/dev/null 2>&1; then
        local nver
        nver=$(node -v)
        local major
        major=$(echo "$nver" | sed 's/^v//' | cut -d. -f1)
        if [[ "$major" -ge 18 ]]; then
            echo -e "${GREEN}$nver (符合 >= 18 要求)${RESET}"
        else
            echo -e "${YELLOW}$nver (Claude Code 要求 Node.js >= 18)${RESET}"
        fi
    else
        echo -e "${RED}未找到 (必须安装 Node.js >= 18)${RESET}"
    fi

    echo -n "npm: "
    if command -v npm >/dev/null 2>&1; then
        echo -e "${GREEN}$(npm -v)${RESET}"
    else
        echo -e "${RED}未找到${RESET}"
    fi

    echo -n "Claude Code CLI: "
    if command -v claude >/dev/null 2>&1; then
        echo -e "${GREEN}$(claude --version 2>/dev/null || echo '已安装')${RESET}"
    else
        echo -e "${YELLOW}未安装${RESET}"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 7. Deployment Guide
# ------------------------------------------------------------

show_guide() {
    clear

    cat <<'EOF'
============================================================
              Claude Code CLI 离线部署流程
============================================================

【一、外网构建机】

1. 运行：
     ./00-install.sh

2. 选择：
     [1] 构建 Claude Code FULL Offline Bundle
   （物料自动下载并保存在 claude-agent 目录）

3. 选择：
     [2] 打包 Offline ZIP
   （在 output/ 目录生成 Claude-Code-FULL-Offline-vx.x.x-win64.zip）


【二、复制到内网环境】

1. 将 output/ 目录下的 ZIP 压缩包复制到内网机器。
2. 解压到目标目录（保持同级目录整洁，所有物料都在 claude-agent/ 中）。


【三、内网一键安装】

1. 在解压目录打开终端（Git Bash 或 PowerShell / CMD）。
2. 执行：
     ./00-install.sh
3. 选择：
     [3] 安装 Claude Code CLI (离线模式)
   （亦可在 PowerShell 中直接运行 .\03-install-offline.ps1）


【四、安装后验证】

1. 在菜单中选择：
     [4] 验证离线环境
2. 亦可在终端输入 `claude --version` 验证。


【五、内网环境变量配置提示】

内网机器通常通过内部反向代理或网关访问 LLM 服务，可在环境中配置：
- PowerShell:
    $env:ANTHROPIC_BASE_URL="http://your-internal-llm-proxy/v1"
    $env:ANTHROPIC_API_KEY="sk-ant-..."
- Bash / CMD:
    export ANTHROPIC_BASE_URL="http://your-internal-llm-proxy/v1"
    export ANTHROPIC_API_KEY="sk-ant-..."
============================================================
EOF

    pause_screen
}

# ------------------------------------------------------------
# Main Loop
# ------------------------------------------------------------

while true; do
    show_header

    echo "  [1] 外网构建机 - 构建 Claude Code Offline Bundle"
    echo
    echo "  [2] 外网构建机 - 打包 Offline ZIP"
    echo
    echo "  [3] 内网机器 - 安装 Claude Code CLI"
    echo
    echo "  [4] 内网机器 - 验证离线环境"
    echo
    echo "  [5] 查看当前文件与物料"
    echo
    echo "  [6] 环境检查 (Node / npm / PowerShell / Claude CLI)"
    echo
    echo "  [7] 查看部署说明"
    echo
    echo "  [0] 退出"
    echo
    echo "============================================================"
    echo

    read -r -p "请选择 [0-7]: " choice

    case "$choice" in
        1)
            build_bundle
            ;;
        2)
            pack_bundle
            ;;
        3)
            install_bundle
            ;;
        4)
            verify_bundle
            ;;
        5)
            show_files
            ;;
        6)
            powershell_check
            ;;
        7)
            show_guide
            ;;
        0)
            echo
            echo "退出 Claude Code 离线部署工具。"
            exit 0
            ;;
        *)
            echo
            echo -e "${RED}无效选项。${RESET}"
            sleep 1
            ;;
    esac
done

