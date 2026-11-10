#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Claude-Offline-Bundle"
$OutputDir  = Join-Path $ScriptRoot "output"

$ClaudeAgentDir      = Join-Path $BundleRoot "claude-agent"
$LocalClaudeAgentDir = Join-Path $ScriptRoot "claude-agent"

# 如果 BundleRoot 不存在但 local claude-agent 存在，则自动组装 BundleRoot
if (-not (Test-Path $ClaudeAgentDir)) {
    if (Test-Path $LocalClaudeAgentDir) {
        New-Item -ItemType Directory -Path $ClaudeAgentDir -Force | Out-Null
        Copy-Item -Path "$LocalClaudeAgentDir\*" -Destination $ClaudeAgentDir -Recurse -Force
    } else {
        throw "找不到构建产物，请先执行 01-build-offline.ps1"
    }
}

$ManifestPath = Join-Path $ClaudeAgentDir "manifest.json"
if (-not (Test-Path $ManifestPath)) {
    $ManifestPath = Join-Path $BundleRoot "manifest.json"
}

$Version = "latest"
if (Test-Path $ManifestPath) {
    $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    $Version = $Manifest.version
} elseif (Test-Path (Join-Path $ClaudeAgentDir "VERSION.txt")) {
    $Version = (Get-Content (Join-Path $ClaudeAgentDir "VERSION.txt") -Raw).Trim()
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Claude Code CLI Offline Packager"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# 1. 生成 Bundle 内的 install-offline.ps1
# ============================================================

$InstallScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$ClaudeAgent = Join-Path $Root "claude-agent"
if (-not (Test-Path $ClaudeAgent)) {
    $ClaudeAgent = $Root
}

$BinDir     = Join-Path $ClaudeAgent "bin"
$PackageDir = Join-Path $ClaudeAgent "npm-packages"
$CacheDir   = Join-Path $ClaudeAgent "npm-cache"

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Claude Code CLI FULL Offline Installer"
Write-Host "============================================================"
Write-Host ""

# 1. 确保 Windows 原生核心程序 (claude.exe) 就绪
$ClaudeExePath = Join-Path $BinDir "claude.exe"

if ((-not (Test-Path $ClaudeExePath)) -or ((Get-Item $ClaudeExePath).Length -lt 50000)) {
    $WinTgz = Get-ChildItem -Path $PackageDir -Filter "*win32-x64*.tgz" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WinTgz) {
        Write-Host "正在从 $($WinTgz.Name) 解压 Windows 原生核心程序 (claude.exe)..." -ForegroundColor Cyan
        $TempExtract = Join-Path $Root "_tmp_install_extract"
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

# 2. Check Node / npm
Write-Host ""
Write-Host "[2] Checking Node.js..."
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "未找到 Node.js，请先安装 Node.js (推荐 >= 18.0.0)。"
}
$NodeVersion = node -v
Write-Host "Node.js 版本: $NodeVersion"

$NodeMajor = [int]($NodeVersion -replace '^v(\d+)\..*$', '$1')
if ($NodeMajor -lt 18) {
    Write-Host "[WARN] Claude Code 官方推荐 Node.js >= 18.0.0，当前版本较低。" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[3] Checking npm..."
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "未找到 npm，请确认 Node.js 安装完整。"
}
npm -v

# 3. Check offline materials
if (-not (Test-Path $CacheDir)) {
    throw "未找到 npm-cache 离线缓存目录: $CacheDir"
}

# 4. Offline install
Write-Host ""
Write-Host "[4] 正在离线安装 Claude Code CLI..."
Write-Host ""

$TgzFiles = @(Get-ChildItem -Path $PackageDir -Filter "*.tgz" -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$WinTgz  = $TgzFiles | Where-Object { $_ -match "win32-x64" } | Select-Object -First 1
$MainTgz = $TgzFiles | Where-Object { $_ -notmatch "win32|linux|darwin" } | Select-Object -First 1

if (-not $MainTgz -and $TgzFiles.Count -gt 0) {
    $MainTgz = $TgzFiles[0]
}

if ($WinTgz -and $MainTgz) {
    Write-Host "同时安装 Claude Code 主包及 Windows 原生依赖包..."
    npm install -g "$WinTgz" "$MainTgz" --cache "$CacheDir" --offline --prefer-offline --no-audit --no-fund --include=optional
} elseif ($MainTgz) {
    npm install -g "$MainTgz" --cache "$CacheDir" --offline --prefer-offline --no-audit --no-fund --include=optional
} else {
    npm install -g "$ClaudeAgent" --cache "$CacheDir" --offline --prefer-offline --no-audit --no-fund --include=optional
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Claude Code 离线安装失败！" -ForegroundColor Red
    exit 1
}

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

# 5. 确保 PATH 包含原生 bin 与 npm 全局 bin
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

# 6. 在当前根目录生成 claude.cmd 快速启动器
$LocalLauncher = Join-Path $Root "claude.cmd"
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

# 7. 创建桌面快捷方式
try {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut((Join-Path $DesktopPath "Claude Code.lnk"))
    $Shortcut.TargetPath = $LocalLauncher
    $Shortcut.WorkingDirectory = $Root
    $Shortcut.Description = "Claude Code CLI"
    $Shortcut.Save()
    Write-Host "[OK] 已在桌面创建快捷方式: Claude Code.lnk" -ForegroundColor Green
} catch {}

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
        Write-Host "提示: 安装完成。请重新打开终端或使用 .\claude.cmd" -ForegroundColor Yellow
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
'@

$InstallScript | Set-Content -Encoding UTF8 (Join-Path $BundleRoot "install-offline.ps1")

# ============================================================
# 2. 生成 Bundle 内的 verify-offline.ps1
# ============================================================

$VerifyScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Continue"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$ClaudeAgent = Join-Path $ScriptRoot "claude-agent"
if (-not (Test-Path $ClaudeAgent)) {
    $ClaudeAgent = Join-Path (Split-Path -Parent $ScriptRoot) "claude-agent"
}
if (-not (Test-Path $ClaudeAgent)) {
    $ClaudeAgent = $ScriptRoot
}

$BinDir     = Join-Path $ClaudeAgent "bin"
$ClaudeExe  = Join-Path $BinDir "claude.exe"
$LocalLauncher = Join-Path $ScriptRoot "claude.cmd"

# 注入当前进程 PATH
if ((Test-Path $BinDir) -and ($env:PATH -notlike "*$BinDir*")) {
    $env:PATH = "$BinDir;$env:PATH"
}

$Failures = 0

function Pass($Text) {
    Write-Host "[PASS] $Text" -ForegroundColor Green
}

function Fail($Text) {
    Write-Host "[FAIL] $Text" -ForegroundColor Red
    $script:Failures++
}

function Warn($Text) {
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Claude Code CLI 离线环境验证"
Write-Host "============================================================"
Write-Host ""

# Node.js
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nver = node -v
    Pass "Node.js: $nver"
    $NodeMajor = [int]($nver -replace '^v(\d+)\..*$', '$1')
    if ($NodeMajor -lt 18) {
        Warn "Node.js 版本低于 18，Claude Code 官方推荐 Node.js >= 18.0.0"
    }
} else {
    Fail "Node.js (未找到，Claude Code 必须依赖 Node.js 18+)"
}

# npm
Write-Host ""
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Pass "npm: $(npm -v)"
} else {
    Fail "npm (未找到)"
}

# Claude Code
Write-Host ""
$ClaudeCmd = Get-Command claude -ErrorAction SilentlyContinue

$TargetExe = $null
if (Test-Path $ClaudeExe) {
    $TargetExe = $ClaudeExe
} elseif ($null -ne $ClaudeCmd) {
    $TargetExe = $ClaudeCmd.Source
} elseif (Test-Path $LocalLauncher) {
    $TargetExe = $LocalLauncher
}

if ($null -ne $TargetExe) {
    Pass "Claude Code CLI 程序"
    Write-Host "路径: $TargetExe"
    Write-Host -NoNewline "版本: "
    & "$TargetExe" --version
} else {
    Fail "Claude Code CLI (未找到可执行程序)"
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
# Claude Code CLI FULL Offline Bundle

Target: Windows 10/11 x64 (Node.js >= 18.0.0)

Version: @anthropic-ai/claude-code@$Version

Included:
- claude-agent/ (bin, npm-cache, npm-packages .tgz)
- 00-install.sh (交互式安装菜单)
- install-offline.ps1
- verify-offline.ps1
- README.md

Install:
  Method 1 (Git Bash / Bash):
    ./00-install.sh
    选择 [3] 离线安装

  Method 2 (PowerShell):
    Set-ExecutionPolicy -Scope Process Bypass
    .\install-offline.ps1

Verify:
    .\verify-offline.ps1

Environment (Intranet Gateway):
  PowerShell:
    `$env:ANTHROPIC_BASE_URL="http://your-internal-llm-proxy/v1"
    `$env:ANTHROPIC_API_KEY="sk-ant-..."

  Bash / CMD:
    export ANTHROPIC_BASE_URL="http://your-internal-llm-proxy/v1"
    export ANTHROPIC_API_KEY="sk-ant-..."
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

$ZipPath = Join-Path $OutputDir "Claude-Code-FULL-Offline-v$Version-win64.zip"

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
