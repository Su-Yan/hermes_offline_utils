#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 定位 claude-agent 目录
$ClaudeAgent = Join-Path $ScriptRoot "claude-agent"
if (-not (Test-Path $ClaudeAgent)) {
    $ClaudeAgent = Join-Path (Split-Path -Parent $ScriptRoot) "claude-agent"
}
if (-not (Test-Path $ClaudeAgent)) {
    $ClaudeAgent = $ScriptRoot
}

$BinDir     = Join-Path $ClaudeAgent "bin"
$PackageDir = Join-Path $ClaudeAgent "npm-packages"
$CacheDir   = Join-Path $ClaudeAgent "npm-cache"

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Claude Code CLI 离线安装"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# 1. 确保 Windows 原生核心程序 (claude.exe) 就绪
# ============================================================

Write-Host "[1/6] 检查原生核心二进制程序..."

$ClaudeExePath = Join-Path $BinDir "claude.exe"

if ((-not (Test-Path $ClaudeExePath)) -or ((Get-Item $ClaudeExePath).Length -lt 50000)) {
    $WinTgz = Get-ChildItem -Path $PackageDir -Filter "*win32-x64*.tgz" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WinTgz) {
        Write-Host "正在从 $($WinTgz.Name) 解压 Windows 原生核心程序 (claude.exe)..." -ForegroundColor Cyan
        $TempExtract = Join-Path $ScriptRoot "_tmp_install_extract"
        if (Test-Path $TempExtract) { Remove-Item -Path $TempExtract -Recurse -Force }
        New-Item -ItemType Directory -Path $TempExtract -Force | Out-Null

        $WinTar = "$env:SystemRoot\System32\tar.exe"
        if (Get-Command 7z -ErrorAction SilentlyContinue) {
            & 7z x "$($WinTgz.FullName)" -so | 7z x -si -ttar -o"$TempExtract" -y | Out-Null
        } elseif (Test-Path $WinTar) {
            & $WinTar -xzf "$($WinTgz.FullName)" -C "$TempExtract"
        } elseif (Get-Command tar -ErrorAction SilentlyContinue) {
            & tar --force-local -xzf "$($WinTgz.FullName)" -C "$TempExtract"
        }

        $FoundExe = Get-ChildItem -Path $TempExtract -Filter "claude.exe" -Recurse -File | Select-Object -First 1
        if ($FoundExe) {
            Copy-Item -Path $FoundExe.FullName -Destination $ClaudeExePath -Force
            $SizeMB = [math]::Round($FoundExe.Length / 1MB, 2)
            Write-Host "[OK] 原生核心程序已提取就绪: $ClaudeExePath ($SizeMB MB)" -ForegroundColor Green
        }

        if (Test-Path $TempExtract) {
            Remove-Item -Path $TempExtract -Recurse -Force
        }
    }
}

if (Test-Path $ClaudeExePath) {
    Write-Host "[OK] 原生核心程序状态正常。" -ForegroundColor Green
} else {
    Write-Host "[WARN] 未在 bin 目录下找到原生 claude.exe，将依赖 npm 全局安装。" -ForegroundColor Yellow
}

# ============================================================
# 2. 检查 Node.js 与 npm 环境
# ============================================================

Write-Host ""
Write-Host "[2/6] 检查 Node.js / npm 环境..."

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "未找到 Node.js，请先安装 Node.js (推荐 >= 18.0.0)。"
}

$NodeVersion = node -v
Write-Host "Node.js 版本: $NodeVersion"

$NodeMajor = [int]($NodeVersion -replace '^v(\d+)\..*$', '$1')
if ($NodeMajor -lt 18) {
    Write-Host "[WARN] Claude Code 官方推荐 Node.js >= 18.0.0，当前版本为 $NodeVersion。" -ForegroundColor Yellow
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "未找到 npm，请确认 Node.js 安装完整。"
}
$NpmVersion = npm -v
Write-Host "npm 版本    : $NpmVersion"

# ============================================================
# 3. 检查离线物料
# ============================================================

Write-Host ""
Write-Host "[3/6] 检查离线物料目录..."

if (-not (Test-Path $CacheDir)) {
    throw "未找到 npm-cache 离线缓存目录: $CacheDir"
}

$TgzFiles = @(Get-ChildItem -Path $PackageDir -Filter "*.tgz" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
if ($TgzFiles.Count -eq 0) {
    throw "未在 $PackageDir 中找到 .tgz 安装包！"
}

$WinTgz  = $TgzFiles | Where-Object { $_ -match "win32-x64" } | Select-Object -First 1
$MainTgz = $TgzFiles | Where-Object { $_ -notmatch "win32|linux|darwin" } | Select-Object -First 1

if (-not $MainTgz -and $TgzFiles.Count -gt 0) {
    $MainTgz = $TgzFiles[0]
}

# ============================================================
# 4. 离线安装 Claude Code
# ============================================================

Write-Host ""
Write-Host "[4/6] 正在执行 npm 纯离线全局安装..."

if ($WinTgz -and $MainTgz) {
    Write-Host "同时安装 Claude Code 主包及 Windows 原生依赖包..."
    npm install -g "$WinTgz" "$MainTgz" `
        --cache "$CacheDir" `
        --offline `
        --prefer-offline `
        --no-audit `
        --no-fund `
        --include=optional
} elseif ($MainTgz) {
    npm install -g "$MainTgz" `
        --cache "$CacheDir" `
        --offline `
        --prefer-offline `
        --no-audit `
        --no-fund `
        --include=optional
} else {
    npm install -g "$ClaudeAgent" `
        --cache "$CacheDir" `
        --offline `
        --prefer-offline `
        --no-audit `
        --no-fund `
        --include=optional
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Claude Code 离线安装失败！" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] npm 全局安装完成。" -ForegroundColor Green

# 修复 npm 全局安装目录下可能存在的 1KB 占位桩 claude.exe
try {
    $NpmPrefix = (npm config get prefix 2>$null).Trim()
    if ($NpmPrefix -and (Test-Path $ClaudeExePath)) {
        $InstalledClaudeExe = Join-Path $NpmPrefix "node_modules\@anthropic-ai\claude-code\bin\claude.exe"
        if ((Test-Path $InstalledClaudeExe) -and ((Get-Item $InstalledClaudeExe).Length -lt 50000)) {
            Write-Host "正在用原生完整程序替换 npm 目录下的占位桩: $InstalledClaudeExe" -ForegroundColor Cyan
            Copy-Item -Path $ClaudeExePath -Destination $InstalledClaudeExe -Force
            Write-Host "[OK] 已成功替换为原生二进制程序。" -ForegroundColor Green
        }
    }
} catch {}

# ============================================================
# 5. 配置环境变量与启动器
# ============================================================

Write-Host ""
Write-Host "[5/6] 配置环境变量与快速启动器..."

# 1. 注入当前进程 PATH
if (Test-Path $BinDir) {
    if ($env:PATH -notlike "*$BinDir*") {
        $env:PATH = "$BinDir;$env:PATH"
    }

    try {
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $UserPath) { $UserPath = "" }
        if ($UserPath -notlike "*$BinDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
            Write-Host "[OK] 已将 Claude Code 原生程序目录写入用户 PATH: $BinDir" -ForegroundColor Green
        }
    } catch {}
}

# 2. 注入 npm 全局路径到 PATH
try {
    $NpmPrefix = (npm config get prefix 2>$null).Trim()
    if ($NpmPrefix -and (Test-Path $NpmPrefix)) {
        if ($env:PATH -notlike "*$NpmPrefix*") {
            $env:PATH = "$NpmPrefix;$env:PATH"
        }
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $UserPath) { $UserPath = "" }
        if ($UserPath -notlike "*$NpmPrefix*") {
            [Environment]::SetEnvironmentVariable("Path", "$NpmPrefix;$UserPath", "User")
        }
    }
} catch {}

# 3. 生成根目录本地快速启动器 claude.cmd
$LocalLauncher = Join-Path $ScriptRoot "claude.cmd"
@"
@echo off
if exist "%~dp0claude-agent\bin\claude.exe" (
    "%~dp0claude-agent\bin\claude.exe" %*
) else if exist "%~dp0bin\claude.exe" (
    "%~dp0bin\claude.exe" %*
) else if exist "%APPDATA%\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe" (
    "%APPDATA%\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe" %*
) else (
    claude %*
)
"@ | Set-Content -Encoding ASCII $LocalLauncher
Write-Host "[OK] 已在根目录生成快速启动器: $LocalLauncher" -ForegroundColor Green

# 4. 创建桌面快捷方式
try {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "Claude Code.lnk"))
    $Shortcut.TargetPath = $LocalLauncher
    $Shortcut.WorkingDirectory = $ScriptRoot
    $Shortcut.Description = "Claude Code CLI"
    $Shortcut.Save()
    Write-Host "[OK] 已在桌面创建快捷方式: Claude Code.lnk" -ForegroundColor Green
} catch {}

# ============================================================
# 6. 验证安装结果
# ============================================================

Write-Host ""
Write-Host "[6/6] 验证安装..."

Write-Host ""
Write-Host "============================================================"
Write-Host " Claude Code CLI 离线安装成功 (INSTALL SUCCESS)"
Write-Host "============================================================"
Write-Host ""

$Tested = $false

if (Test-Path $ClaudeExePath) {
    Write-Host "Claude Code 原生程序: $ClaudeExePath"
    Write-Host -NoNewline "Claude Code 版本: "
    & "$ClaudeExePath" --version
    $Tested = $true
} elseif (Test-Path $LocalLauncher) {
    Write-Host -NoNewline "Claude Code 版本 (启动器): "
    & "$LocalLauncher" --version
    $Tested = $true
}

if (-not $Tested) {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Host -NoNewline "Claude Code 版本: "
        claude --version
    } else {
        Write-Host "提示: 安装完成。请重新打开 CMD / PowerShell 窗口使 PATH 生效。" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " 【使用方式说明】" -ForegroundColor Cyan
Write-Host " 1. 打开新 CMD / PowerShell 窗口，直接输入: claude"
Write-Host " 2. 在当前安装包目录下直接运行: .\claude.cmd"
Write-Host " 3. 双击桌面【Claude Code】快捷方式"
Write-Host ""
Write-Host " 【内网 API 反向代理配置提示】" -ForegroundColor Cyan
Write-Host ' $env:ANTHROPIC_BASE_URL="http://your-internal-llm-proxy/v1"'
Write-Host ' $env:ANTHROPIC_API_KEY="sk-ant-..."'
Write-Host "============================================================"
Write-Host ""
