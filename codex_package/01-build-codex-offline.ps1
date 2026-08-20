#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex CLI npm 离线安装包制作脚本
#
# 所有路径均为相对于本脚本所在目录的相对路径
#
# 使用：
#   powershell -ExecutionPolicy Bypass -File .\build-codex-offline.ps1
# ============================================================

# ------------------------------------------------------------
# 获取脚本所在目录
# ------------------------------------------------------------

$Root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}

$PackageName = "@openai/codex"

$DownloadDir = Join-Path $Root "npm-packages"
$CacheDir    = Join-Path $Root "npm-cache"
$InstallDir  = Join-Path $Root "test-install"
$LogDir      = Join-Path $Root "logs"
$DeployDir   = Join-Path $Root "deployment"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Offline Package Builder"
Write-Host "============================================================"
Write-Host ""

Write-Host "Root directory:"
Write-Host "  $Root"
Write-Host ""

# ------------------------------------------------------------
# 1. 检查 Node.js / npm
# ------------------------------------------------------------

Write-Host "[1/10] Checking Node.js and npm..." -ForegroundColor Cyan

try {

    $NodeVersion = node -v
    $NpmVersion  = npm -v

}
catch {

    Write-Host ""
    Write-Host "ERROR: Node.js or npm was not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install Node.js first."
    exit 1
}

Write-Host "Node.js : $NodeVersion"
Write-Host "npm     : $NpmVersion"

# ------------------------------------------------------------
# 2. 创建目录
# ------------------------------------------------------------

Write-Host ""
Write-Host "[2/10] Creating directories..." -ForegroundColor Cyan

$Directories = @(
    $DownloadDir,
    $CacheDir,
    $InstallDir,
    $LogDir,
    $DeployDir
)

foreach ($Directory in $Directories) {

    if (!(Test-Path $Directory)) {

        New-Item `
            -ItemType Directory `
            -Path $Directory `
            -Force | Out-Null
    }
}

# ------------------------------------------------------------
# 3. 获取 Codex 当前版本
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/10] Getting Codex version..." -ForegroundColor Cyan

$Version = npm view $PackageName version

if ([string]::IsNullOrWhiteSpace($Version)) {

    Write-Host ""
    Write-Host "ERROR: Failed to get Codex version." -ForegroundColor Red
    exit 1
}

Write-Host "Codex version: $Version" -ForegroundColor Green

Set-Content `
    -Path (Join-Path $Root "VERSION.txt") `
    -Value $Version `
    -Encoding UTF8

# ------------------------------------------------------------
# 4. 下载 Codex npm package
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/10] Downloading Codex npm package..." -ForegroundColor Cyan

Push-Location $DownloadDir

try {

    npm pack "$PackageName@$Version"

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: npm pack failed." -ForegroundColor Red
        exit 1
    }

}
finally {

    Pop-Location
}

$CodexPackage = Get-ChildItem `
    -Path $DownloadDir `
    -Filter "*.tgz" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $CodexPackage) {

    Write-Host ""
    Write-Host "ERROR: Codex npm package was not found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Downloaded package:"
Write-Host "  $($CodexPackage.Name)" -ForegroundColor Green

# ------------------------------------------------------------
# 5. 准备独立 npm cache
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/10] Preparing npm cache..." -ForegroundColor Cyan

Write-Host "Cache directory:"
Write-Host "  $CacheDir"

npm cache add `
    $CodexPackage.FullName `
    --cache $CacheDir

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "ERROR: Failed to add package to npm cache." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 6. 尝试下载依赖到离线 cache
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/10] Preparing dependencies..." -ForegroundColor Cyan

$TempPackageJson = Join-Path $InstallDir "package.json"

@"
{
  "name": "codex-offline-test",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@openai/codex": "$Version"
  }
}
"@ | Set-Content `
    -Path $TempPackageJson `
    -Encoding UTF8

Push-Location $InstallDir

try {

    Write-Host ""
    Write-Host "Downloading npm dependencies into offline cache..."

    npm install `
        --package-lock=false `
        --cache $CacheDir `
        --prefer-offline `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: Failed to download dependencies." -ForegroundColor Red
        exit 1
    }

}
finally {

    Pop-Location
}

# ------------------------------------------------------------
# 7. 删除测试安装目录
# ------------------------------------------------------------

Write-Host ""
Write-Host "[7/10] Cleaning temporary test installation..." -ForegroundColor Cyan

if (Test-Path $InstallDir) {

    Remove-Item `
        -Path $InstallDir `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $InstallDir `
    -Force | Out-Null

# ------------------------------------------------------------
# 8. 真正进行 Offline 安装测试
# ------------------------------------------------------------

Write-Host ""
Write-Host "[8/10] Testing offline installation..." -ForegroundColor Cyan

$TestPackageJson = Join-Path $InstallDir "package.json"

@"
{
  "name": "codex-offline-test",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@openai/codex": "$Version"
  }
}
"@ | Set-Content `
    -Path $TestPackageJson `
    -Encoding UTF8

Push-Location $InstallDir

try {

    Write-Host ""
    Write-Host "Running npm install --offline..."
    Write-Host ""

    npm install `
        --offline `
        --cache $CacheDir `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "============================================================"
        Write-Host " OFFLINE INSTALL TEST FAILED"
        Write-Host "============================================================"
        Write-Host ""

        Write-Host "Some npm dependencies are missing from the offline cache."
        Write-Host ""

        exit 1
    }

}
finally {

    Pop-Location
}

Write-Host ""
Write-Host "Offline installation test PASSED." -ForegroundColor Green

# ------------------------------------------------------------
# 9. 创建部署脚本
# ------------------------------------------------------------

Write-Host ""
Write-Host "[9/10] Creating deployment scripts..." -ForegroundColor Cyan

# ------------------------------------------------------------
# install.ps1
# ------------------------------------------------------------

$InstallScript = @'
#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex CLI Offline Installer
# 所有路径均相对于 install.ps1 所在目录
# ============================================================

$Root = $PSScriptRoot

$PackageDir = Join-Path $Root "..\npm-packages"
$CacheDir   = Join-Path $Root "..\npm-cache"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Offline Installer"
Write-Host "============================================================"
Write-Host ""

Write-Host "Package directory:"
Write-Host "  $PackageDir"

Write-Host ""
Write-Host "npm cache:"
Write-Host "  $CacheDir"

# ------------------------------------------------------------
# 检查 npm
# ------------------------------------------------------------

try {

    $NodeVersion = node -v
    $NpmVersion  = npm -v

}
catch {

    Write-Host ""
    Write-Host "ERROR: Node.js/npm not found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Node.js : $NodeVersion"
Write-Host "npm     : $NpmVersion"

# ------------------------------------------------------------
# 检查 package
# ------------------------------------------------------------

$Package = Get-ChildItem `
    -Path $PackageDir `
    -Filter "*.tgz" |
    Select-Object -First 1

if ($null -eq $Package) {

    Write-Host ""
    Write-Host "ERROR: Codex npm package not found." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 检查 npm cache
# ------------------------------------------------------------

if (!(Test-Path $CacheDir)) {

    Write-Host ""
    Write-Host "ERROR: npm cache not found." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# 离线安装
# ------------------------------------------------------------

Write-Host ""
Write-Host "Installing Codex CLI..."
Write-Host ""

npm install -g `
    $Package.FullName `
    --offline `
    --cache $CacheDir `
    --no-audit `
    --no-fund

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " INSTALLATION FAILED"
    Write-Host "============================================================"
    exit 1
}

# ------------------------------------------------------------
# 验证
# ------------------------------------------------------------

Write-Host ""
Write-Host "Checking Codex..."
Write-Host ""

$Codex = Get-Command codex -ErrorAction SilentlyContinue

if ($null -eq $Codex) {

    Write-Host ""
    Write-Host "WARNING: codex command was not found in current PATH." `
        -ForegroundColor Yellow

    Write-Host ""
    Write-Host "Please close and reopen PowerShell, then run:"
    Write-Host ""
    Write-Host "    codex --version"

}
else {

    Write-Host "Codex executable:"
    Write-Host "  $($Codex.Source)"

    Write-Host ""
    Write-Host "Codex version:"
    codex --version

    Write-Host ""
    Write-Host "Codex CLI installed successfully." `
        -ForegroundColor Green
}

Write-Host ""
'@

Set-Content `
    -Path (Join-Path $DeployDir "install.ps1") `
    -Value $InstallScript `
    -Encoding UTF8

# ------------------------------------------------------------
# check.ps1
# ------------------------------------------------------------

$CheckScript = @'
#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Installation Check"
Write-Host "============================================================"
Write-Host ""

Write-Host "[1] Node.js"
Write-Host "--------------------------------------------"

node -v

Write-Host ""
Write-Host "[2] npm"
Write-Host "--------------------------------------------"

npm -v

Write-Host ""
Write-Host "[3] Codex"
Write-Host "--------------------------------------------"

$Codex = Get-Command codex -ErrorAction SilentlyContinue

if ($null -eq $Codex) {

    Write-Host "Codex command NOT FOUND." -ForegroundColor Red

    Write-Host ""
    Write-Host "Current PATH:"
    Write-Host $env:PATH

    exit 1
}

Write-Host "Codex executable:"
Write-Host $Codex.Source

Write-Host ""
Write-Host "Codex version:"

codex --version

Write-Host ""
Write-Host "Installation check PASSED." -ForegroundColor Green
'@

Set-Content `
    -Path (Join-Path $DeployDir "check.ps1") `
    -Value $CheckScript `
    -Encoding UTF8

# ------------------------------------------------------------
# uninstall.ps1
# ------------------------------------------------------------

$UninstallScript = @'
#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Uninstaller"
Write-Host "============================================================"
Write-Host ""

npm uninstall -g @openai/codex

if ($LASTEXITCODE -eq 0) {

    Write-Host ""
    Write-Host "Codex CLI removed successfully." `
        -ForegroundColor Green
}
else {

    Write-Host ""
    Write-Host "Codex uninstall failed." `
        -ForegroundColor Red
}
'@

Set-Content `
    -Path (Join-Path $DeployDir "uninstall.ps1") `
    -Value $UninstallScript `
    -Encoding UTF8

# ------------------------------------------------------------
# README
# ------------------------------------------------------------

$Readme = @"
# Codex CLI Offline Installation Package

## Package

@openai/codex@$Version

## Build Environment

Node.js: $NodeVersion

npm: $NpmVersion

## Directory Structure

npm-packages\
    Codex npm package

npm-cache\
    Complete npm offline cache

deployment\
    install.ps1
    check.ps1
    uninstall.ps1

## Installation

Copy the entire package directory to the offline Windows computer.

Open PowerShell.

Run:

    Set-ExecutionPolicy -Scope Process Bypass

Then:

    cd deployment

    .\install.ps1

After installation:

    codex --version

Check:

    .\check.ps1

## Uninstall

    .\uninstall.ps1

## Important

The package contains the Codex CLI software and npm dependencies.

The Codex CLI itself still needs access to a supported model service
for actual AI operations.

If the target environment is completely isolated from the Internet,
an internally accessible model/API endpoint is required.
"@

Set-Content `
    -Path (Join-Path $Root "README.md") `
    -Value $Readme `
    -Encoding UTF8

# ------------------------------------------------------------
# 10. 最终检查
# ------------------------------------------------------------

Write-Host ""
Write-Host "[10/10] Final verification..." -ForegroundColor Cyan

Write-Host ""
Write-Host "Package files:"
Write-Host "--------------------------------------------"

Get-ChildItem `
    -Path $Root `
    -Recurse `
    -File |
    ForEach-Object {

        $Relative = $_.FullName.Substring($Root.Length + 1)

        Write-Host $Relative
    }

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex offline package created successfully."
Write-Host "============================================================"
Write-Host ""

Write-Host "Package root:"
Write-Host "  $Root" -ForegroundColor Green

Write-Host ""
Write-Host "Copy this entire directory to the offline computer."
Write-Host ""

# ------------------------------------------------------------
# ZIP
# ------------------------------------------------------------

$ParentDir = Split-Path $Root -Parent
$FolderName = Split-Path $Root -Leaf

$ZipFile = Join-Path `
    $ParentDir `
    "$FolderName-$Version.zip"

if (Test-Path $ZipFile) {

    Remove-Item `
        $ZipFile `
        -Force
}

Write-Host "Creating ZIP package..."

Compress-Archive `
    -Path "$Root\*" `
    -DestinationPath $ZipFile `
    -CompressionLevel Optimal

Write-Host ""
Write-Host "ZIP package:"
Write-Host "  $ZipFile" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================"
Write-Host " DONE"
Write-Host "============================================================"