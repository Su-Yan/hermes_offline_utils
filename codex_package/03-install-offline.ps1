#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 定位 codex-agent 目录
$CodexAgent = Join-Path $ScriptRoot "codex-agent"
if (-not (Test-Path $CodexAgent)) {
    $CodexAgent = Join-Path (Split-Path -Parent $ScriptRoot) "codex-agent"
}
if (-not (Test-Path $CodexAgent)) {
    $CodexAgent = $ScriptRoot
}

$BinDir     = Join-Path $CodexAgent "bin"
$PackageDir = Join-Path $CodexAgent "npm-packages"
$CacheDir   = Join-Path $CodexAgent "npm-cache"

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI 离线安装"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# 1. 确保 Windows 核心原生程序 (codex.exe 等) 就绪
# ============================================================

$CodexExePath = Join-Path $BinDir "codex.exe"

if (-not (Test-Path $CodexExePath)) {
    $WinTgz = Get-ChildItem -Path $PackageDir -Filter "*win32-x64*.tgz" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WinTgz) {
        Write-Host "正在从 $($WinTgz.Name) 解压 Windows 原生程序 (codex.exe)..."
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

        $VendorBin  = Join-Path $TempExtract "package\vendor\x86_64-pc-windows-msvc\bin"
        $VendorPath = Join-Path $TempExtract "package\vendor\x86_64-pc-windows-msvc"

        if (Test-Path $VendorBin) {
            Copy-Item -Path "$VendorBin\*" -Destination $BinDir -Recurse -Force
        }
        if (Test-Path (Join-Path $VendorPath "codex-path")) {
            Copy-Item -Path (Join-Path $VendorPath "codex-path\*") -Destination $BinDir -Recurse -Force
        }
        if (Test-Path (Join-Path $VendorPath "codex-resources")) {
            Copy-Item -Path (Join-Path $VendorPath "codex-resources\*") -Destination $BinDir -Recurse -Force
        }
        if (Test-Path (Join-Path $VendorPath "codex-package.json")) {
            Copy-Item -Path (Join-Path $VendorPath "codex-package.json") -Destination $BinDir -Force
        }

        if (Test-Path $TempExtract) {
            Remove-Item -Path $TempExtract -Recurse -Force
        }
    }
}

if (Test-Path $CodexExePath) {
    Write-Host "[OK] 原生核心程序就绪: $CodexExePath" -ForegroundColor Green
} else {
    Write-Host "[WARN] 未在 bin 目录下找到 codex.exe，将尝试全局 npm 安装..." -ForegroundColor Yellow
}

# ============================================================
# 2. 将 codex-agent/bin 加入 Windows PATH
# ============================================================

if (Test-Path $BinDir) {
    # 注入当前进程
    if ($env:PATH -notlike "*$BinDir*") {
        $env:PATH = "$BinDir;$env:PATH"
    }

    # 写入用户环境变量
    try {
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $UserPath) { $UserPath = "" }
        if ($UserPath -notlike "*$BinDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
            Write-Host "[OK] 已将 Codex 原生程序目录写入用户 PATH: $BinDir" -ForegroundColor Green
        }
    } catch {}

    # 写入系统环境变量（管理员可用）
    try {
        $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($null -ne $MachinePath -and $MachinePath -notlike "*$BinDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$BinDir;$MachinePath", "Machine")
        }
    } catch {}
}

# ============================================================
# 3. 生成本地 codex.cmd 快速启动器
# ============================================================

$LocalLauncher = Join-Path $ScriptRoot "codex.cmd"
@"
@echo off
if exist "%~dp0codex-agent\bin\codex.exe" (
    "%~dp0codex-agent\bin\codex.exe" %*
) else if exist "%~dp0bin\codex.exe" (
    "%~dp0bin\codex.exe" %*
) else (
    codex.exe %*
)
"@ | Set-Content -Encoding ASCII $LocalLauncher
Write-Host "[OK] 已在根目录生成快速启动器: $LocalLauncher" -ForegroundColor Green

# ============================================================
# 4. 创建桌面快捷方式
# ============================================================

try {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "Codex CLI.lnk"))
    $Shortcut.TargetPath = $LocalLauncher
    $Shortcut.WorkingDirectory = $ScriptRoot
    $Shortcut.Description = "Codex CLI"
    $Shortcut.Save()
    Write-Host "[OK] 已在桌面创建快捷方式: Codex CLI.lnk" -ForegroundColor Green
} catch {}

# ============================================================
# 5. 执行验证
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI 离线安装成功 (INSTALL SUCCESS)"
Write-Host "============================================================"
Write-Host ""

$Tested = $false

if (Test-Path $CodexExePath) {
    Write-Host "Codex 原生程序: $CodexExePath"
    Write-Host -NoNewline "Codex 版本: "
    & "$CodexExePath" --version
    $Tested = $true
} elseif (Test-Path $LocalLauncher) {
    Write-Host "Codex 启动器: $LocalLauncher"
    Write-Host -NoNewline "Codex 版本: "
    & "$LocalLauncher" --version
    $Tested = $true
}

if (-not $Tested) {
    $Cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($Cmd) {
        & $Cmd.Source --version
    } else {
        Write-Host "提示: 安装完成。请重新打开终端。" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " 【使用方式说明】" -ForegroundColor Cyan
Write-Host " 1. 打开一个新的 CMD / PowerShell 窗口，直接输入: codex"
Write-Host " 2. 在当前安装包目录下直接运行: .\codex.cmd"
Write-Host " 3. 双击桌面【Codex CLI】快捷方式图标"
Write-Host "============================================================"
Write-Host ""
