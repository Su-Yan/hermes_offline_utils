#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex CLI Offline Builder
#
# 所有路径均基于当前脚本目录
# 不使用任何固定盘符
# ============================================================

$Root = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}

$PackageName = "@openai/codex"

$NpmCacheDir = Join-Path $Root "npm-cache"
$PackageDir  = Join-Path $Root "npm-packages"
$TestDir     = Join-Path $Root "test-install"
$LogDir      = Join-Path $Root "logs"
$DeployDir   = Join-Path $Root "deployment"

$PackageJson = Join-Path $Root "package.json"
$PackageLock = Join-Path $Root "package-lock.json"
$VersionFile = Join-Path $Root "VERSION.txt"
$ShaFile     = Join-Path $Root "SHA256SUMS.txt"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Offline Builder"
Write-Host "============================================================"
Write-Host ""

Write-Host "Root:"
Write-Host "  $Root"
Write-Host ""

# ============================================================
# 1. 检查 Node / npm
# ============================================================

Write-Host "[1/12] Checking Node.js..." -ForegroundColor Cyan

try {

    $NodeVersion = node -v
    $NpmVersion  = npm -v

}
catch {

    Write-Host ""
    Write-Host "ERROR: Node.js/npm not found." -ForegroundColor Red
    exit 1
}

Write-Host "Node.js : $NodeVersion"
Write-Host "npm     : $NpmVersion"

# ============================================================
# 2. 创建目录
# ============================================================

Write-Host ""
Write-Host "[2/12] Preparing directories..." -ForegroundColor Cyan

$Directories = @(
    $NpmCacheDir,
    $PackageDir,
    $TestDir,
    $LogDir,
    $DeployDir
)

foreach ($Directory in $Directories) {

    New-Item `
        -ItemType Directory `
        -Path $Directory `
        -Force | Out-Null
}

# ============================================================
# 3. 获取 Codex 版本
# ============================================================

Write-Host ""
Write-Host "[3/12] Getting Codex version..." -ForegroundColor Cyan

$Version = npm view $PackageName version

if ([string]::IsNullOrWhiteSpace($Version)) {

    Write-Host ""
    Write-Host "ERROR: Cannot get Codex version." -ForegroundColor Red
    exit 1
}

Write-Host "Codex version:"
Write-Host "  $Version" -ForegroundColor Green

Set-Content `
    -Path $VersionFile `
    -Value $Version `
    -Encoding UTF8

# ============================================================
# 4. 创建 package.json
# ============================================================

Write-Host ""
Write-Host "[4/12] Creating package.json..." -ForegroundColor Cyan

$PackageJsonContent = @"
{
  "name": "codex-offline-build",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@openai/codex": "$Version"
  }
}
"@

Set-Content `
    -Path $PackageJson `
    -Value $PackageJsonContent `
    -Encoding UTF8

# ============================================================
# 5. 生成 package-lock.json
# ============================================================

Write-Host ""
Write-Host "[5/12] Generating package-lock.json..." -ForegroundColor Cyan

Push-Location $Root

try {

    npm install `
        --package-lock-only `
        --ignore-scripts `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: Failed to generate package-lock.json." `
            -ForegroundColor Red

        exit 1
    }

}
finally {

    Pop-Location
}

# ============================================================
# 6. 下载完整依赖
# ============================================================

Write-Host ""
Write-Host "[6/12] Downloading complete npm dependency tree..." `
    -ForegroundColor Cyan

Push-Location $Root

try {

    npm ci `
        --cache $NpmCacheDir `
        --prefer-offline `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: npm dependency download failed." `
            -ForegroundColor Red

        exit 1
    }

}
finally {

    Pop-Location
}

# ============================================================
# 7. 保存 Codex npm package
# ============================================================

Write-Host ""
Write-Host "[7/12] Packing Codex npm package..." -ForegroundColor Cyan

Push-Location $PackageDir

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

# ============================================================
# 8. 清理 node_modules
# ============================================================

Write-Host ""
Write-Host "[8/12] Cleaning temporary node_modules..." `
    -ForegroundColor Cyan

$NodeModules = Join-Path $Root "node_modules"

if (Test-Path $NodeModules) {

    Remove-Item `
        -Path $NodeModules `
        -Recurse `
        -Force
}

# ============================================================
# 9. 真正的 Offline npm ci 测试
# ============================================================

Write-Host ""
Write-Host "[9/12] Running TRUE offline installation test..." `
    -ForegroundColor Cyan

if (Test-Path $TestDir) {

    Remove-Item `
        -Path $TestDir `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $TestDir `
    -Force | Out-Null

Copy-Item `
    -Path $PackageJson `
    -Destination $TestDir

Copy-Item `
    -Path $PackageLock `
    -Destination $TestDir

Push-Location $TestDir

try {

    Write-Host ""
    Write-Host "Executing:"
    Write-Host "  npm ci --offline"
    Write-Host ""

    npm ci `
        --offline `
        --cache $NpmCacheDir `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "============================================================"
        Write-Host " OFFLINE TEST FAILED"
        Write-Host "============================================================"

        exit 1
    }

}
finally {

    Pop-Location
}

Write-Host ""
Write-Host "TRUE OFFLINE INSTALL TEST PASSED." `
    -ForegroundColor Green

# ============================================================
# 10. 生成 SHA256
# ============================================================

Write-Host ""
Write-Host "[10/12] Generating SHA256 checksums..." `
    -ForegroundColor Cyan

if (Test-Path $ShaFile) {

    Remove-Item `
        -Path $ShaFile `
        -Force
}

$FilesToHash = @(
    $PackageJson,
    $PackageLock,
    $VersionFile
)

Get-ChildItem `
    -Path $PackageDir `
    -Recurse `
    -File |
    ForEach-Object {

        $FilesToHash += $_.FullName
    }

foreach ($File in $FilesToHash) {

    if (Test-Path $File) {

        $Hash = Get-FileHash `
            -Path $File `
            -Algorithm SHA256

        $Relative = $File.Substring($Root.Length + 1)

        Add-Content `
            -Path $ShaFile `
            -Value "$($Hash.Hash)  $Relative" `
            -Encoding UTF8
    }
}

# ============================================================
# 11. 生成部署脚本
# ============================================================

Write-Host ""
Write-Host "[11/12] Creating deployment scripts..." `
    -ForegroundColor Cyan

# ------------------------------------------------------------
# install.ps1
# ------------------------------------------------------------

$InstallScript = @'
#Requires -Version 5.1

$ErrorActionPreference = "Stop"

# ============================================================
# Codex CLI Offline Installer
# ============================================================

$Root = Split-Path `
    -Parent `
    $PSScriptRoot

$PackageJson = Join-Path `
    $Root `
    "package.json"

$PackageLock = Join-Path `
    $Root `
    "package-lock.json"

$CacheDir = Join-Path `
    $Root `
    "npm-cache"

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI Offline Installer"
Write-Host "============================================================"
Write-Host ""

# ------------------------------------------------------------
# Node / npm
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# 检查文件
# ------------------------------------------------------------

if (!(Test-Path $PackageJson)) {
    throw "package.json not found."
}

if (!(Test-Path $PackageLock)) {
    throw "package-lock.json not found."
}

if (!(Test-Path $CacheDir)) {
    throw "npm-cache not found."
}

# ------------------------------------------------------------
# 全局安装
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3] Installing Codex CLI..."
Write-Host ""

npm install `
    -g `
    "$Root\package.json" `
    --cache $CacheDir `
    --offline `
    --no-audit `
    --no-fund

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "Codex installation FAILED." `
        -ForegroundColor Red

    exit 1
}

# ------------------------------------------------------------
# 验证
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4] Checking Codex..."

$Codex = Get-Command `
    codex `
    -ErrorAction SilentlyContinue

if ($null -eq $Codex) {

    Write-Host ""
    Write-Host "Codex command not found." `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "Codex:"
Write-Host "  $($Codex.Source)"

Write-Host ""
Write-Host "Version:"

codex --version

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI installation SUCCESS"
Write-Host "============================================================"
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
Write-Host " Codex CLI Check"
Write-Host "============================================================"
Write-Host ""

Write-Host "[Node.js]"
node -v

Write-Host ""
Write-Host "[npm]"
npm -v

Write-Host ""
Write-Host "[Codex]"

$Codex = Get-Command `
    codex `
    -ErrorAction SilentlyContinue

if ($null -eq $Codex) {

    Write-Host "Codex NOT FOUND." `
        -ForegroundColor Red

    exit 1
}

Write-Host "Path:"
Write-Host "  $($Codex.Source)"

Write-Host ""
Write-Host "Version:"

codex --version

Write-Host ""
Write-Host "Codex check PASSED." `
    -ForegroundColor Green
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
Write-Host "Uninstalling Codex CLI..."

npm uninstall `
    -g `
    @openai/codex

if ($LASTEXITCODE -ne 0) {

    Write-Host ""
    Write-Host "Uninstall FAILED." `
        -ForegroundColor Red

    exit 1
}

Write-Host ""
Write-Host "Codex CLI uninstalled." `
    -ForegroundColor Green
'@

Set-Content `
    -Path (Join-Path $DeployDir "uninstall.ps1") `
    -Value $UninstallScript `
    -Encoding UTF8

# ============================================================
# 12. 生成 README
# ============================================================

Write-Host ""
Write-Host "[12/12] Creating README..." -ForegroundColor Cyan

$Readme = @"
# Codex CLI Offline Package

## Version

@openai/codex@$Version

## Build Environment

Node.js: $NodeVersion

npm: $NpmVersion

## Offline Installation

Open PowerShell as Administrator.

Run:

    Set-ExecutionPolicy -Scope Process Bypass

Then:

    cd deployment

    .\install.ps1

Check:

    .\check.ps1

## Uninstall

    .\uninstall.ps1

## Important

This package contains Codex CLI and its npm dependency cache.

The CLI still needs a model service for AI functionality.

A completely isolated network therefore requires an internally
accessible compatible model/API endpoint.
"@

Set-Content `
    -Path (Join-Path $Root "README.md") `
    -Value $Readme `
    -Encoding UTF8

# ============================================================
# 创建 ZIP
# ============================================================

Write-Host ""
Write-Host "Creating offline ZIP..." -ForegroundColor Cyan

# 清理测试安装目录，避免将临时测试的 node_modules 打包进压缩包
if (Test-Path $TestDir) {
    Remove-Item `
        -Path $TestDir `
        -Recurse `
        -Force
}

$BuildDir = Join-Path $Root "_build"
$BundleDir = Join-Path $BuildDir "Codex-Offline-Bundle"

if (Test-Path $BundleDir) {
    Remove-Item `
        -Path $BundleDir `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $BundleDir `
    -Force | Out-Null

$BundleItems = @(
    $PackageJson,
    $PackageLock,
    $VersionFile,
    $ShaFile,
    (Join-Path $Root "README.md"),
    $DeployDir,
    $NpmCacheDir,
    $PackageDir
)

foreach ($Item in $BundleItems) {
    if (Test-Path $Item) {
        Copy-Item `
            -Path $Item `
            -Destination $BundleDir `
            -Recurse `
            -Force
    }
}

$Parent = Split-Path `
    -Parent `
    $Root

$Name = Split-Path `
    -Leaf `
    $Root

$Zip = Join-Path `
    $Parent `
    "$Name-$Version.zip"

if (Test-Path $Zip) {

    Remove-Item `
        $Zip `
        -Force
}

# 优先尝试 7-Zip（速度更快且无文件占用问题），否则回退到 Compress-Archive
$SevenZipCmd = Get-Command 7z -ErrorAction SilentlyContinue
if (-not $SevenZipCmd) {
    $SevenZipCmd = Get-Command 7za -ErrorAction SilentlyContinue
}

if ($SevenZipCmd) {
    & $SevenZipCmd.Source a -tzip "$Zip" "$BundleDir\*" -mx=7 -mmt=on | Out-Null
} else {
    Compress-Archive `
        -Path "$BundleDir\*" `
        -DestinationPath $Zip `
        -CompressionLevel Optimal
}

# 清理临时 staging 目录
if (Test-Path $BuildDir) {
    Remove-Item `
        -Path $BuildDir `
        -Recurse `
        -Force
}

Write-Host ""
Write-Host "============================================================"
Write-Host " BUILD COMPLETE"
Write-Host "============================================================"
Write-Host ""

Write-Host "Version:"
Write-Host "  $Version"

Write-Host ""
Write-Host "Offline package:"
Write-Host "  $Zip" -ForegroundColor Green

Write-Host ""