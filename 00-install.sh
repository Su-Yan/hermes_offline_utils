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

run_ps1() {
    local script="$1"

    if [[ ! -f "$script" ]]; then
        echo
        echo -e "${RED}[错误] 找不到 $script${RESET}"
        pause_screen
        return 1
    fi

    echo
    echo -e "${CYAN}执行：$script${RESET}"
    echo

    powershell.exe \
        -NoProfile \
        -ExecutionPolicy Bypass \
        -File "$SCRIPT_DIR/$script"

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
    echo "             Hermes Agent 离线部署工具"
    echo
    echo "============================================================"
    echo
    echo "当前目录："
    echo "  $SCRIPT_DIR"
    echo
}

# ------------------------------------------------------------
# Build
# ------------------------------------------------------------

build_bundle() {

    clear

    echo
    echo "============================================================"
    echo "  1. 构建 FULL Offline Bundle"
    echo "============================================================"
    echo

    echo "适用于：外网 Windows 构建机"
    echo
    echo "将准备："
    echo
    echo "  - Hermes Agent"
    echo "  - Python"
    echo "  - Node.js"
    echo "  - Git / Git Bash"
    echo "  - agent-browser"
    echo "  - Playwright Chromium"
    echo "  - ffmpeg"
    echo "  - ripgrep"
    echo "  - npm cache"
    echo "  - Electron cache"
    echo "  - Electron Builder cache"
    echo "  - Hermes Desktop"
    echo

    echo -e "${YELLOW}注意：该步骤需要互联网。${RESET}"
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
# Pack
# ------------------------------------------------------------

pack_bundle() {

    clear

    echo
    echo "============================================================"
    echo "  2. 打包 FULL Offline Bundle"
    echo "============================================================"
    echo

    if [[ ! -d "_build/Hermes-Offline-Bundle" ]]; then
        echo -e "${RED}[错误] 找不到：${RESET}"
        echo
        echo "  _build/Hermes-Offline-Bundle"
        echo
        echo "请先执行 [1] 构建。"
        pause_screen
        return
    fi

    read -r -p "确认开始打包？[y/N] " answer

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
# Install
# ------------------------------------------------------------

install_bundle() {

    clear

    echo
    echo "============================================================"
    echo "  3. 安装 Hermes FULL Offline Bundle"
    echo "============================================================"
    echo

    echo "适用于：内网 Windows"
    echo
    echo "本步骤不应该访问互联网。"
    echo
    echo "不会执行："
    echo
    echo "  npm install"
    echo "  npm ci"
    echo "  pip install"
    echo "  uv pip install"
    echo "  npx playwright install"
    echo "  git clone"
    echo

    read -r -p "确认开始离线安装？[y/N] " answer

    case "$answer" in
        y|Y)
            run_ps1 "03-install-offline.ps1"
            ;;
        *)
            echo "已取消。"
            sleep 1
            ;;
    esac
}

# ------------------------------------------------------------
# Verify
# ------------------------------------------------------------

verify_bundle() {

    clear

    echo
    echo "============================================================"
    echo "  4. 检查 Hermes 离线环境"
    echo "============================================================"
    echo

    echo "将检查："
    echo
    echo "  [1] Hermes CLI"
    echo "  [2] Python"
    echo "  [3] Node.js"
    echo "  [4] Git"
    echo "  [5] Git Bash"
    echo "  [6] agent-browser"
    echo "  [7] Playwright Chromium"
    echo "  [8] ffmpeg"
    echo "  [9] ripgrep"
    echo " [10] Hermes Desktop"
    echo " [11] Hermes doctor"
    echo

    run_ps1 "04-verify-offline.ps1"
}

# ------------------------------------------------------------
# Files
# ------------------------------------------------------------

show_files() {

    clear

    echo
    echo "============================================================"
    echo "  当前目录"
    echo "============================================================"
    echo

    echo "PowerShell："
    echo

    find . -maxdepth 1 -type f -name "*.ps1" -printf "  %f\n" 2>/dev/null

    echo
    echo "Shell："
    echo

    find . -maxdepth 1 -type f -name "*.sh" -printf "  %f\n" 2>/dev/null

    echo
    echo "Build："
    echo

    if [[ -d "_build" ]]; then
        find "_build" -maxdepth 2 -type d | head -30
    else
        echo "  [不存在]"
    fi

    echo
    echo "Output："
    echo

    if [[ -d "output" ]]; then
        find "output" -maxdepth 1 -type f -printf "  %f\n"
    else
        echo "  [不存在]"
    fi

    pause_screen
}

# ------------------------------------------------------------
# PowerShell check
# ------------------------------------------------------------

powershell_check() {

    clear

    echo
    echo "============================================================"
    echo "  PowerShell 环境检查"
    echo "============================================================"
    echo

    echo "PowerShell："
    powershell.exe -NoProfile -Command '$PSVersionTable | Format-List'

    echo
    echo "Windows Architecture："
    powershell.exe -NoProfile -Command '[Environment]::Is64BitOperatingSystem'

    echo
    echo "Execution Policy："
    powershell.exe -NoProfile -Command 'Get-ExecutionPolicy -List'

    echo
    echo "Node："
    node --version 2>/dev/null || echo "  未找到"

    echo
    echo "npm："
    npm --version 2>/dev/null || echo "  未找到"

    echo
    echo "Git："
    git --version 2>/dev/null || echo "  未找到"

    pause_screen
}

# ------------------------------------------------------------
# Guide
# ------------------------------------------------------------

show_guide() {

    clear

    cat <<'EOF'

============================================================
              Hermes Agent 离线部署流程
============================================================

【一、外网 Windows 构建机】

运行：

    ./00-install.sh

选择：

    [1] 构建 FULL Offline Bundle

然后：

    [2] 打包 FULL Offline Bundle

最终得到：

    output/
        Hermes-FULL-Offline-xxxxxxxx-win64.zip


【二、复制到内网】

把 ZIP 文件复制到内网 Windows。

解压后，确保：

    00-hermes-offline.sh
    01-build-offline.ps1
    02-pack-offline.ps1
    03-install-offline.ps1
    04-verify-offline.ps1

都可以访问。


【三、内网安装】

运行：

    ./00-install.sh

选择：

    [3] 安装 Hermes


【四、安装后检查】

选择：

    [4] 检查 Hermes 离线环境


【五、需要检查的组件】

    Hermes CLI
    Hermes Desktop
    Python
    Node.js
    Git
    Git Bash
    agent-browser
    Playwright Chromium
    Electron cache
    Electron Builder cache
    ffmpeg
    ripgrep


【六、内网原则】

内网机器不要执行：

    npm install
    npm ci
    pip install
    uv pip install
    npx playwright install
    git clone

所有依赖应该来自 Offline Bundle。


============================================================

EOF

    pause_screen
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

while true; do

    show_header

    echo "  [1] 外网构建机 - 构建 FULL Offline Bundle"
    echo
    echo "  [2] 外网构建机 - 打包 Offline ZIP"
    echo
    echo "  [3] 内网 Windows - 安装 Hermes"
    echo
    echo "  [4] 内网 Windows - 验证离线环境"
    echo
    echo "  [5] 查看当前文件"
    echo
    echo "  [6] PowerShell 环境检查"
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
            echo "退出 Hermes Offline Deployment."
            exit 0
            ;;

        *)
            echo
            echo -e "${RED}无效选项。${RESET}"
            sleep 1
            ;;

    esac

done