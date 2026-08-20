#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Hermes-Offline-Bundle"
$OutputDir  = Join-Path $ScriptRoot "output"

if (-not (Test-Path $BundleRoot)) {
    throw "找不到 Bundle，请先执行 01-build-offline.ps1"
}

$ManifestPath = Join-Path $BundleRoot "manifest.json"

if (-not (Test-Path $ManifestPath)) {
    throw "manifest.json 不存在。"
}

$Manifest = Get-Content `
    $ManifestPath `
    -Raw |
    ConvertFrom-Json

# ============================================================
# Install script
# ============================================================

$InstallScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$Hermes = Join-Path `
    $Root `
    "hermes-agent\venv\Scripts\hermes.exe"

$HermesBin = Join-Path `
    $Root `
    "hermes-agent\venv\Scripts"

$Python = Join-Path `
    $Root `
    "hermes-agent\venv\Scripts\python.exe"

$NodeDir = Join-Path `
    $Root `
    "runtime\node"

$GitDir = Join-Path `
    $Root `
    "runtime\git"

$GitBash = Join-Path `
    $GitDir `
    "bin\bash.exe"

$AgentBrowserDir = Join-Path `
    $Root `
    "runtime\agent-browser\node_modules\.bin"

$AgentBrowser = Join-Path `
    $AgentBrowserDir `
    "agent-browser.cmd"

$PlaywrightDir = Join-Path `
    $Root `
    "runtime\playwright-browsers"

$FfmpegDir = Join-Path `
    $Root `
    "tools\ffmpeg"

$RgDir = Join-Path `
    $Root `
    "tools\ripgrep"

$Ffmpeg = Join-Path `
    $FfmpegDir `
    "ffmpeg.exe"

$Rg = Join-Path `
    $RgDir `
    "rg.exe"

$HermesHome = Join-Path `
    $env:LOCALAPPDATA `
    "hermes"

Write-Host ""
Write-Host "============================================================"
Write-Host " Hermes FULL Offline Installer"
Write-Host "============================================================"
Write-Host ""

# ============================================================
# Validation
# ============================================================

$Required = @(
    $Hermes,
    $Python,
    $GitBash,
    $AgentBrowser
)

foreach ($File in $Required) {

    if (-not (Test-Path $File)) {
        throw "缺少离线组件：$File"
    }
}

if (-not (Test-Path $PlaywrightDir)) {
    throw "缺少 Playwright Chromium：$PlaywrightDir"
}

# ============================================================
# Hermes home
# ============================================================

New-Item `
    -ItemType Directory `
    -Path $HermesHome `
    -Force | Out-Null

# ============================================================
# Environment variables
# ============================================================

[Environment]::SetEnvironmentVariable(
    "HERMES_HOME",
    $HermesHome,
    "User"
)

[Environment]::SetEnvironmentVariable(
    "HERMES_GIT_BASH_PATH",
    $GitBash,
    "User"
)

[Environment]::SetEnvironmentVariable(
    "PLAYWRIGHT_BROWSERS_PATH",
    $PlaywrightDir,
    "User"
)

[Environment]::SetEnvironmentVariable(
    "HERMES_AGENT_BROWSER_ROOT",
    (Join-Path $Root "runtime\agent-browser"),
    "User"
)

if (Test-Path $Ffmpeg) {
    [Environment]::SetEnvironmentVariable(
        "HERMES_FFMPEG",
        $Ffmpeg,
        "User"
    )
}

if (Test-Path $Rg) {
    [Environment]::SetEnvironmentVariable(
        "HERMES_RIPGREP",
        $Rg,
        "User"
    )
}

# ============================================================
# PATH
# ============================================================

$UserPath = [Environment]::GetEnvironmentVariable(
    "Path",
    "User"
)

$PathEntries = @(
    $HermesBin,
    $NodeDir,
    (Join-Path $GitDir "bin"),
    $AgentBrowserDir,
    $FfmpegDir,
    $RgDir
)

foreach ($Entry in $PathEntries) {

    if (
        (Test-Path $Entry) -and
        ($UserPath -notlike "*$Entry*")
    ) {

        $UserPath = "$Entry;$UserPath"
    }
}

[Environment]::SetEnvironmentVariable(
    "Path",
    $UserPath,
    "User"
)

# 当前进程立即可用
$env:HERMES_HOME = $HermesHome
$env:HERMES_GIT_BASH_PATH = $GitBash
$env:PLAYWRIGHT_BROWSERS_PATH = $PlaywrightDir

$env:PATH = `
    "$HermesBin;$NodeDir;$(Join-Path $GitDir 'bin');$AgentBrowserDir;$FfmpegDir;$RgDir;$env:PATH"

# ============================================================
# Rebuild venv with bundle Python (fixes uv trampoline)
# ============================================================

Write-Host ""
Write-Host "重建 Python 虚拟环境（使用 Bundle Python，修复 uv trampoline）..."

$BundlePython = Join-Path $Root "runtime\python\python.exe"
$PipWheelsDir = Join-Path $Root "cache\pip-wheels"

if (-not (Test-Path $BundlePython)) {
    throw "Bundle Python 不存在：$BundlePython"
}

if (-not (Test-Path $PipWheelsDir)) {
    throw "pip wheels 缓存不存在：$PipWheelsDir"
}

& $BundlePython -m venv (Join-Path $Root "hermes-agent\venv") --clear

if ($LASTEXITCODE -ne 0) {
    throw "venv 重建失败。"
}

Push-Location (Join-Path $Root "hermes-agent")

& $Python -m pip install `
    -e ".[all]" `
    --no-index `
    --find-links $PipWheelsDir `
    --quiet

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "pip 离线安装失败。"
}

Pop-Location

Write-Host "venv 重建完成。"

# ============================================================
# Verify dependencies
# ============================================================

Write-Host ""
Write-Host "Python:"
& $Python --version

Write-Host ""
Write-Host "Node:"
& (Join-Path $NodeDir "node.exe") --version

Write-Host ""
Write-Host "Git:"
& (Join-Path $GitDir "bin\git.exe") --version

Write-Host ""
Write-Host "Git Bash:"
& $GitBash --version

Write-Host ""
Write-Host "agent-browser:"
& $AgentBrowser --version

if ($LASTEXITCODE -ne 0) {
    throw "agent-browser 无法执行。"
}

Write-Host ""
Write-Host "ffmpeg:"
if (Test-Path $Ffmpeg) {
    & $Ffmpeg -version | Select-Object -First 1
} else {
    Write-Host "(not included)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "ripgrep:"
if (Test-Path $Rg) {
    & $Rg --version
} else {
    Write-Host "(not included)" -ForegroundColor Yellow
}

# ============================================================
# Hermes
# ============================================================

Write-Host ""
Write-Host "Hermes:"

& $Hermes --version

if ($LASTEXITCODE -ne 0) {
    throw "Hermes CLI 无法启动。"
}

# ============================================================
# Offline browser test
# ============================================================

Write-Host ""
Write-Host "测试 agent-browser..."

& $AgentBrowser --version

if ($LASTEXITCODE -ne 0) {
    throw "agent-browser 测试失败。"
}

# ============================================================
# Launchers
# ============================================================

$CliLauncher = Join-Path `
    $Root `
    "hermes.cmd"

@"
@echo off
set "HERMES_HOME=%LOCALAPPDATA%\hermes"
set "HERMES_GIT_BASH_PATH=%~dp0runtime\git\bin\bash.exe"
set "PLAYWRIGHT_BROWSERS_PATH=%~dp0runtime\playwright-browsers"
set "HERMES_AGENT_BROWSER_ROOT=%~dp0runtime\agent-browser"
set "HERMES_FFMPEG=%~dp0tools\ffmpeg\ffmpeg.exe"
set "HERMES_RIPGREP=%~dp0tools\ripgrep\rg.exe"
set "PATH=%~dp0hermes-agent\venv\Scripts;%~dp0runtime\node;%~dp0runtime\git\bin;%~dp0runtime\agent-browser\node_modules\.bin;%~dp0tools\ffmpeg;%~dp0tools\ripgrep;%PATH%"

"%~dp0hermes-agent\venv\Scripts\hermes.exe" %*
"@ |
    Set-Content `
        -Encoding ASCII `
        $CliLauncher

$DesktopLauncher = Join-Path `
    $Root `
    "start-hermes-desktop.cmd"

@"
@echo off
set "HERMES_HOME=%LOCALAPPDATA%\hermes"
set "HERMES_GIT_BASH_PATH=%~dp0runtime\git\bin\bash.exe"
set "PLAYWRIGHT_BROWSERS_PATH=%~dp0runtime\playwright-browsers"
set "HERMES_AGENT_BROWSER_ROOT=%~dp0runtime\agent-browser"
set "HERMES_FFMPEG=%~dp0tools\ffmpeg\ffmpeg.exe"
set "HERMES_RIPGREP=%~dp0tools\ripgrep\rg.exe"
set "PATH=%~dp0hermes-agent\venv\Scripts;%~dp0runtime\node;%~dp0runtime\git\bin;%~dp0runtime\agent-browser\node_modules\.bin;%~dp0tools\ffmpeg;%~dp0tools\ripgrep;%PATH%"

"%~dp0hermes-agent\venv\Scripts\hermes.exe" desktop --skip-build
"@ |
    Set-Content `
        -Encoding ASCII `
        $DesktopLauncher

# ============================================================
# Shortcuts
# ============================================================

$DesktopPath = [Environment]::GetFolderPath("Desktop")

$Shell = New-Object -ComObject WScript.Shell

$Shortcut = $Shell.CreateShortcut(
    (Join-Path $DesktopPath "Hermes Desktop.lnk")
)

$Shortcut.TargetPath = $DesktopLauncher
$Shortcut.WorkingDirectory = $Root
$Shortcut.Description = "Hermes Agent Desktop"
$Shortcut.Save()

$Shortcut = $Shell.CreateShortcut(
    (Join-Path $DesktopPath "Hermes CLI.lnk")
)

$Shortcut.TargetPath = "powershell.exe"
$Shortcut.Arguments = `
    "-NoExit -Command `"& '$CliLauncher'`""

$Shortcut.WorkingDirectory = $Root
$Shortcut.Description = "Hermes Agent CLI"
$Shortcut.Save()

Write-Host ""
Write-Host "============================================================"
Write-Host " INSTALL SUCCESS"
Write-Host "============================================================"
Write-Host ""

Write-Host "Hermes:"
Write-Host $Hermes

Write-Host ""
Write-Host "agent-browser:"
Write-Host $AgentBrowser

Write-Host ""
Write-Host "Chromium:"
Write-Host $PlaywrightDir

Write-Host ""
Write-Host "ffmpeg:"
Write-Host $Ffmpeg

Write-Host ""
Write-Host "ripgrep:"
Write-Host $Rg

Write-Host ""
Write-Host "请完全关闭当前 PowerShell，再重新打开。"
Write-Host ""

Read-Host "按 Enter 退出"
'@

$InstallScript |
    Set-Content `
        -Encoding UTF8 `
        (Join-Path $BundleRoot "install-offline.ps1")

# ============================================================
# Verify script
# ============================================================

$VerifyScript = @'
#requires -Version 5.1

$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

$Hermes = Join-Path $Root "hermes-agent\venv\Scripts\hermes.exe"
$Python = Join-Path $Root "hermes-agent\venv\Scripts\python.exe"

$Node = Join-Path $Root "runtime\node\node.exe"

$Git = Join-Path $Root "runtime\git\bin\git.exe"
$Bash = Join-Path $Root "runtime\git\bin\bash.exe"

$AgentBrowser = Join-Path `
    $Root `
    "runtime\agent-browser\node_modules\.bin\agent-browser.cmd"

$Playwright = Join-Path `
    $Root `
    "runtime\playwright-browsers"

$Ffmpeg = Join-Path `
    $Root `
    "tools\ffmpeg\ffmpeg.exe"

$Rg = Join-Path `
    $Root `
    "tools\ripgrep\rg.exe"

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
Write-Host " Hermes FULL Offline Verification"
Write-Host "============================================================"
Write-Host ""

# Hermes
if (Test-Path $Hermes) {
    Pass "Hermes CLI"
    & $Hermes --version
}
else {
    Fail "Hermes CLI"
}

# Python
if (Test-Path $Python) {
    Pass "Python 3.11"
    & $Python --version
}
else {
    Fail "Python"
}

# Node
if (Test-Path $Node) {
    Pass "Node"
    & $Node --version
}
else {
    Fail "Node"
}

# Git
if (Test-Path $Git) {
    Pass "Git"
    & $Git --version
}
else {
    Fail "Git"
}

# Bash
if (Test-Path $Bash) {
    Pass "Git Bash"
}
else {
    Fail "Git Bash"
}

# agent-browser
if (Test-Path $AgentBrowser) {

    Pass "agent-browser"

    & $AgentBrowser --version

    if ($LASTEXITCODE -ne 0) {
        Fail "agent-browser 无法运行"
    }

}
else {
    Fail "agent-browser.cmd"
}

# Chromium
if (Test-Path $Playwright) {

    $ChromiumFiles = Get-ChildItem `
        $Playwright `
        -Recurse `
        -File `
        -ErrorAction SilentlyContinue

    if ($ChromiumFiles.Count -gt 0) {
        Pass "Playwright Chromium"
    }
    else {
        Fail "Playwright Chromium 目录为空"
    }

}
else {
    Fail "Playwright browser cache"
}

# ffmpeg
if (Test-Path $Ffmpeg) {

    Pass "ffmpeg"

    & $Ffmpeg -version |
        Select-Object -First 1

}
else {
    Fail "ffmpeg"
}

# ripgrep
if (Test-Path $Rg) {

    Pass "ripgrep"

    & $Rg --version

}
else {
    Fail "ripgrep"
}

# Environment
Write-Host ""
Write-Host "Environment:"
Write-Host ""

Write-Host "HERMES_HOME:"
Write-Host $env:HERMES_HOME

Write-Host ""
Write-Host "HERMES_GIT_BASH_PATH:"
Write-Host $env:HERMES_GIT_BASH_PATH

Write-Host ""
Write-Host "PLAYWRIGHT_BROWSERS_PATH:"
Write-Host $env:PLAYWRIGHT_BROWSERS_PATH

# Hermes doctor
Write-Host ""
Write-Host "============================================================"
Write-Host " Hermes Doctor"
Write-Host "============================================================"
Write-Host ""

if (Test-Path $Hermes) {
    & $Hermes doctor
}

Write-Host ""
Write-Host "============================================================"

if ($Failures -eq 0) {

    Write-Host " VERIFICATION SUCCESS" -ForegroundColor Green
    Write-Host "============================================================"

}
else {

    Write-Host " VERIFICATION FAILED: $Failures item(s)" `
        -ForegroundColor Red

    Write-Host "============================================================"
}

Write-Host ""

exit $Failures
'@

$VerifyScript |
    Set-Content `
        -Encoding UTF8 `
        (Join-Path $BundleRoot "verify-offline.ps1")

# ============================================================
# README
# ============================================================

$Readme = @"
# Hermes Agent FULL Offline Bundle

Target:
Windows 10/11 x64

Included:

- Hermes Agent
- Python 3.11
- Node.js
- Portable Git / Git Bash
- agent-browser
- Playwright Chromium
- ffmpeg
- ripgrep
- Electron cache
- electron-builder cache
- npm cache
- Hermes Desktop

Hermes commit:
$($Manifest.commit)

Install:

    Set-ExecutionPolicy -Scope Process Bypass

    .\install-offline.ps1

Restart PowerShell.

Verify:

    .\verify-offline.ps1

CLI:

    hermes --version

Desktop:

    hermes desktop --skip-build

Browser:

    agent-browser --version

ffmpeg:

    ffmpeg -version

ripgrep:

    rg --version

IMPORTANT:

The target machine must NOT run:

    npm install
    npm ci
    pip install
    uv pip install
    npx playwright install
    git clone

Those dependencies are supposed to come from this bundle.
"@

$Readme |
    Set-Content `
        -Encoding UTF8 `
        (Join-Path $BundleRoot "README-OFFLINE.txt")

# ============================================================
# Utility scripts
# ============================================================

Info "打包工具脚本到 utils\ ..."

$UtilsDir = Join-Path $BundleRoot "utils"
Ensure-Dir $UtilsDir

$UtilsFiles = @(
    "00-install.sh",
    "01-build-offline.ps1",
    "02-pack-offline.ps1",
    "03-install-offline.ps1",
    "04-verify-offline.ps1",
    "README.md"
)

foreach ($F in $UtilsFiles) {
    $Src = Join-Path $ScriptRoot $F
    if (Test-Path $Src) {
        Copy-Item $Src (Join-Path $UtilsDir $F) -Force
        Ok "  utils: $F"
    } else {
        Warn "  utils: $F 不存在，跳过。"
    }
}

# ============================================================
# ZIP
# ============================================================

if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
}

New-Item `
    -ItemType Directory `
    -Path $OutputDir `
    -Force | Out-Null

$ShortCommit = $Manifest.commit.Substring(0, 12)

$ZipPath = Join-Path `
    $OutputDir `
    "Hermes-FULL-Offline-$ShortCommit-win64.zip"

Write-Host ""
Write-Host "正在压缩完整离线包..."
Write-Host ""

# 优先使用 7-Zip（多线程，速度约快 5-10 倍）
$SevenZipExe = $null

$SevenZipCmd = Get-Command 7z  -ErrorAction SilentlyContinue
if (-not $SevenZipCmd) {
    $SevenZipCmd = Get-Command 7za -ErrorAction SilentlyContinue
}

if ($SevenZipCmd) {
    $SevenZipExe = $SevenZipCmd.Source
} else {
    $SevenZipCandidates = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe",
        "$env:USERPROFILE\scoop\apps\7zip\current\7z.exe"
    )
    foreach ($c in $SevenZipCandidates) {
        if (Test-Path $c) {
            $SevenZipExe = $c
            break
        }
    }
}

if ($SevenZipExe) {

    Info "使用 7-Zip 压缩（多线程 -mmt=on，压缩级别 -mx=3）..."

    & $SevenZipExe a -tzip -mx=3 -mmt=on $ZipPath "$BundleRoot\*"

    if ($LASTEXITCODE -ne 0) {
        throw "7-Zip 压缩失败，退出码：$LASTEXITCODE"
    }

} else {

    Warn "未找到 7-Zip，使用内置 Compress-Archive（单线程，较慢）。"
    Warn "建议安装 7-Zip 以加速：winget install 7zip.7zip"

    Compress-Archive `
        -Path "$BundleRoot\*" `
        -DestinationPath $ZipPath `
        -CompressionLevel Fastest
}

$SizeGB = [Math]::Round(
    ((Get-Item $ZipPath).Length / 1GB),
    2
)

Write-Host ""
Write-Host "============================================================"
Write-Host " PACKAGE SUCCESS"
Write-Host "============================================================"
Write-Host ""

Write-Host "ZIP:"
Write-Host $ZipPath

Write-Host ""
Write-Host "Size:"
Write-Host "$SizeGB GB"

Write-Host ""
Write-Host "Hermes commit:"
Write-Host $Manifest.commit

Write-Host ""

Read-Host "按 Enter 退出"