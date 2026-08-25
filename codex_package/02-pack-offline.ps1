#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Codex-Offline-Bundle"
$OutputDir  = Join-Path $ScriptRoot "output"

$CodexAgentDir = Join-Path $BundleRoot "codex-agent"
$LocalCodexAgentDir = Join-Path $ScriptRoot "codex-agent"

# 如果 BundleRoot 不存在但 local codex-agent 存在，则自动组装 BundleRoot
if (-not (Test-Path $CodexAgentDir)) {
    if (Test-Path $LocalCodexAgentDir) {
        New-Item -ItemType Directory -Path $CodexAgentDir -Force | Out-Null
        Copy-Item -Path "$LocalCodexAgentDir\*" -Destination $CodexAgentDir -Recurse -Force
    } else {
        throw "找不到构建产物，请先执行 01-build-offline.ps1"
    }
}

$ManifestPath = Join-Path $CodexAgentDir "manifest.json"
if (-not (Test-Path $ManifestPath)) {
    $ManifestPath = Join-Path $BundleRoot "manifest.json"
}

$Version = "latest"
if (Test-Path $ManifestPath) {
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $Version = $Manifest.version
} elseif (Test-Path (Join-Path $CodexAgentDir "VERSION.txt")) {
    $Version = (Get-Content (Join-Path $CodexAgentDir "VERSION.txt") -Raw).Trim()
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Offline Packager"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# 1. 生成 Bundle 内的 install-offline.ps1
# ============================================================

$InstallScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$CodexAgent = Join-Path $Root "codex-agent"
if (-not (Test-Path $CodexAgent)) {
    $CodexAgent = $Root
}

$CacheDir   = Join-Path $CodexAgent "npm-cache"
$PackageDir = Join-Path $CodexAgent "npm-packages"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI FULL Offline Installer"
Write-Host "============================================================"
Write-Host ""

# 1. Check Node / npm
Write-Host "[1] Checking Node.js..."
node -v
if ($LASTEXITCODE -ne 0) {
    throw "Node.js is not available."
}

Write-Host ""
Write-Host "[2] Checking npm..."
npm -v
if ($LASTEXITCODE -ne 0) {
    throw "npm is not available."
}

# 2. Check offline materials
if (-not (Test-Path $CacheDir)) {
    throw "未找到 npm-cache 离线缓存目录: $CacheDir"
}

# 3. Offline install
Write-Host ""
Write-Host "[3] 正在离线安装 Codex CLI..."
Write-Host ""

$TgzFiles = @(Get-ChildItem -Path $PackageDir -Filter "*.tgz" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

$WinTgz  = $TgzFiles | Where-Object { $_ -match "win32-x64" } | Select-Object -First 1
$MainTgz = $TgzFiles | Where-Object { $_ -notmatch "win32|linux|darwin" } | Select-Object -First 1

if ($WinTgz -and $MainTgz) {
    Write-Host "安装 Codex 主包及 Windows x64 二进制组件..."
    Write-Host "  - 二进制包: $WinTgz"
    Write-Host "  - CLI 主包: $MainTgz"
    npm install -g $WinTgz $MainTgz --cache $CacheDir --offline --prefer-offline --no-audit --no-fund
} elseif ($MainTgz) {
    Write-Host "安装 Codex 主包: $MainTgz"
    npm install -g $MainTgz --cache $CacheDir --offline --prefer-offline --no-audit --no-fund
} elseif ($TgzFiles.Count -gt 0) {
    npm install -g $TgzFiles --cache $CacheDir --offline --prefer-offline --no-audit --no-fund
} else {
    Write-Host "从 codex-agent 目录离线安装: $CodexAgent"
    npm install `
        -g `
        "$CodexAgent" `
        --cache $CacheDir `
        --offline `
        --prefer-offline `
        --no-audit `
        --no-fund
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Codex 离线安装失败！" -ForegroundColor Red
    exit 1
}

# 1. 确保 codex-agent/bin 目录中的 Windows 核心程序就绪
$BinDir = Join-Path $CodexAgent "bin"
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

$CodexExePath = Join-Path $BinDir "codex.exe"
if (-not (Test-Path $CodexExePath)) {
    $WinTgz = Get-ChildItem -Path $PackageDir -Filter "*win32-x64*.tgz" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WinTgz) {
        Write-Host "正在从 $($WinTgz.Name) 解压 Windows 原生程序 (codex.exe)..."
        $TempExtract = Join-Path $Root "_tmp_install_extract"
        if (Test-Path $TempExtract) { Remove-Item -Path $TempExtract -Recurse -Force }
        $WinTar = "C:\Windows\System32\tar.exe"
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

# 2. 将 codex-agent/bin 目录直接写入系统 / 用户 PATH
if (Test-Path $BinDir) {
    if ($env:PATH -notlike "*$BinDir*") {
        $env:PATH = "$BinDir;$env:PATH"
    }

    try {
        $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $UserPath) { $UserPath = "" }
        if ($UserPath -notlike "*$BinDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$BinDir;$UserPath", "User")
            Write-Host "[OK] 已将 Codex 核心程序目录写入用户 PATH: $BinDir" -ForegroundColor Green
        }
    } catch {}

    try {
        $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($null -ne $MachinePath -and $MachinePath -notlike "*$BinDir*") {
            [Environment]::SetEnvironmentVariable("Path", "$BinDir;$MachinePath", "Machine")
        }
    } catch {}
}

# 3. 在当前根目录生成 codex.cmd 快速启动器（本地任意双击或输入 codex 即可运行）
$LocalLauncher = Join-Path $Root "codex.cmd"
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

# 4. 创建桌面快捷方式
try {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "Codex CLI.lnk"))
    $Shortcut.TargetPath = $LocalLauncher
    $Shortcut.WorkingDirectory = $Root
    $Shortcut.Description = "Codex CLI"
    $Shortcut.Save()
    Write-Host "[OK] 已在桌面创建快捷方式: Codex CLI.lnk" -ForegroundColor Green
} catch {}

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI 离线安装成功 (INSTALL SUCCESS)"
Write-Host "============================================================"
Write-Host ""

$CodexExe = Join-Path $BinDir "codex.exe"
if (Test-Path $CodexExe) {
    Write-Host "Codex 核心程序: $CodexExe"
    Write-Host -NoNewline "Codex 版本: "
    & "$CodexExe" --version
} else {
    codex --version
}

Write-Host ""
Write-Host "============================================================"
Write-Host " 【使用方式说明】" -ForegroundColor Cyan
Write-Host " 1. 打开一个新的 CMD / PowerShell 窗口，直接输入: codex"
Write-Host " 2. 在当前安装包目录下直接运行: .\codex.cmd"
Write-Host " 3. 双击桌面【Codex CLI】快捷方式图标"
Write-Host "============================================================"
Write-Host ""
'@

$InstallScript | Set-Content -Encoding UTF8 (Join-Path $BundleRoot "install-offline.ps1")

# ============================================================
# 2. 生成 Bundle 内的 verify-offline.ps1
# ============================================================

$VerifyScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Continue"

$Failures = 0

function Pass($Text) {
    Write-Host "[PASS] $Text" -ForegroundColor Green
}

function Fail($Text) {
    Write-Host "[FAIL] $Text" -ForegroundColor Red
    $script:Failures++
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI 离线环境验证"
Write-Host "============================================================"
Write-Host ""

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    Pass "Node.js"
    node -v
} else {
    Pass "Node.js (非必须，Codex 采用原生独立二进制)"
}

# npm
Write-Host ""
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Pass "npm"
    npm -v
} else {
    Pass "npm (非必须)"
}

# Codex
Write-Host ""
$CodexAgent = Join-Path $ScriptRoot "codex-agent"
if (-not (Test-Path $CodexAgent)) {
    $CodexAgent = Join-Path (Split-Path -Parent $ScriptRoot) "codex-agent"
}

$NativeCodex   = Join-Path $CodexAgent "bin\codex.exe"
$LocalLauncher = Join-Path $ScriptRoot "codex.cmd"
$CodexCmd      = Get-Command codex -ErrorAction SilentlyContinue

$TargetExe = $null
if (Test-Path $NativeCodex) {
    $TargetExe = $NativeCodex
} elseif ($null -ne $CodexCmd) {
    $TargetExe = $CodexCmd.Source
} elseif (Test-Path $LocalLauncher) {
    $TargetExe = $LocalLauncher
}

if ($null -ne $TargetExe) {
    Pass "Codex CLI 原生程序"
    Write-Host "路径: $TargetExe"
    Write-Host -NoNewline "版本: "
    & "$TargetExe" --version
} else {
    Fail "Codex CLI (未找到可执行程序)"
}

Write-Host ""
Write-Host "============================================================"

if ($Failures -eq 0) {
    Write-Host " VERIFICATION SUCCESS" -ForegroundColor Green
    Write-Host "============================================================"
} else {
    Write-Host " VERIFICATION FAILED: $Failures item(s)" -ForegroundColor Red
    Write-Host "============================================================"
}

Write-Host ""
exit $Failures
'@

$VerifyScript | Set-Content -Encoding UTF8 (Join-Path $BundleRoot "verify-offline.ps1")

# ============================================================
# 3. 生成 README-OFFLINE.txt
# ============================================================

$Readme = @"
# Codex CLI FULL Offline Bundle

Target: Windows 10/11 x64

Version: @openai/codex@$Version

Included:
- codex-agent/ (npm-cache, npm-packages .tgz)
- 00-install.sh (交互式安装菜单)
- install-offline.ps1
- verify-offline.ps1

Install:
  Method 1 (Git Bash / Bash):
    ./00-install.sh
    选择 [2] 离线安装

  Method 2 (PowerShell):
    Set-ExecutionPolicy -Scope Process Bypass
    .\install-offline.ps1

Verify:
    .\verify-offline.ps1
"@

$Readme | Set-Content -Encoding UTF8 (Join-Path $BundleRoot "README-OFFLINE.txt")

# ============================================================
# 4. 打包工具脚本
# ============================================================

Write-Host "[INFO] 打包交互与工具脚本..." -ForegroundColor Cyan

$UtilsFiles = @(
    "00-install.sh",
    "01-build-offline.ps1",
    "02-pack-offline.ps1",
    "03-install-offline.ps1",
    "04-verify-offline.ps1",
    "README.md"
)

# 复制到 BundleRoot 根目录（方便解压后直接执行 ./00-install.sh）
foreach ($F in $UtilsFiles) {
    $Src = Join-Path $ScriptRoot $F
    if (Test-Path $Src) {
        Copy-Item $Src (Join-Path $BundleRoot $F) -Force
    }
}

# 同时备份一份在 utils/ 目录
$UtilsDir = Join-Path $BundleRoot "utils"
if (-not (Test-Path $UtilsDir)) {
    New-Item -ItemType Directory -Path $UtilsDir -Force | Out-Null
}
foreach ($F in $UtilsFiles) {
    $Src = Join-Path $ScriptRoot $F
    if (Test-Path $Src) {
        Copy-Item $Src (Join-Path $UtilsDir $F) -Force
    }
}

# ============================================================
# 5. 压缩为 ZIP
# ============================================================

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$ZipPath = Join-Path $OutputDir "Codex-FULL-Offline-v$Version-win64.zip"

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Write-Host ""
Write-Host "正在压缩离线安装包..." -ForegroundColor Cyan
Write-Host "目标路径: $ZipPath"
Write-Host ""

$SevenZipCmd = Get-Command 7z -ErrorAction SilentlyContinue
if (-not $SevenZipCmd) {
    $SevenZipCmd = Get-Command 7za -ErrorAction SilentlyContinue
}

if ($SevenZipCmd) {
    Write-Host "使用 7-Zip 多线程压缩..."
    & $SevenZipCmd.Source a -tzip "$ZipPath" "$BundleRoot\*" -mx=7 -mmt=on | Out-Null
} else {
    Compress-Archive `
        -Path "$BundleRoot\*" `
        -DestinationPath $ZipPath `
        -CompressionLevel Optimal
}

$ZipSize = (Get-Item $ZipPath).Length / 1MB

Write-Host ""
Write-Host "============================================================"
Write-Host " PACK SUCCESS"
Write-Host "============================================================"
Write-Host ""
Write-Host "版本: $Version"
Write-Host "离线压缩包: $ZipPath ($("{0:N2}" -f $ZipSize) MB)"
Write-Host ""
