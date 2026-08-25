#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Codex-Offline-Bundle"

$CodexAgentDir      = Join-Path $BundleRoot "codex-agent"
$LocalCodexAgentDir = Join-Path $ScriptRoot "codex-agent"

$PackageName = "@openai/codex"

function Info($Text) {
    Write-Host "[INFO] $Text" -ForegroundColor Cyan
}

function Ok($Text) {
    Write-Host "[ OK ] $Text" -ForegroundColor Green
}

function Warn($Text) {
    Write-Host "[WARN] $Text" -ForegroundColor Yellow
}

function Ensure-Dir($Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Require-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "找不到命令：$Name"
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Codex CLI FULL Offline Builder"
Write-Host "============================================================"
Write-Host ""

Ensure-Dir $WorkRoot
Ensure-Dir $BundleRoot
Ensure-Dir $CodexAgentDir
Ensure-Dir $LocalCodexAgentDir

$NpmCacheDir = Join-Path $CodexAgentDir "npm-cache"
$PackageDir  = Join-Path $CodexAgentDir "npm-packages"
$TestDir     = Join-Path $WorkRoot "test-install"

Ensure-Dir $NpmCacheDir
Ensure-Dir $PackageDir

# ============================================================
# 1. 基础工具检查
# ============================================================

Info "[1/9] 检查构建机 Node.js / npm 环境..."

Require-Command node
Require-Command npm

$NodeVersion = node -v
$NpmVersion  = npm -v

Ok "Node.js : $NodeVersion"
Ok "npm     : $NpmVersion"

# ============================================================
# 2. 获取 Codex 版本
# ============================================================

Write-Host ""
Info "[2/9] 获取 Codex 最新版本..."

$Version = npm view $PackageName version
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "无法获取 $PackageName 的版本号。"
}

Ok "Codex 目标版本: $Version"

$VersionFile = Join-Path $CodexAgentDir "VERSION.txt"
Set-Content -Path $VersionFile -Value $Version -Encoding UTF8

# ============================================================
# 3. 创建 package.json
# ============================================================

Write-Host ""
Info "[3/9] 在 codex-agent 中创建 package.json..."

$PackageJson = Join-Path $CodexAgentDir "package.json"
$PackageLock = Join-Path $CodexAgentDir "package-lock.json"

$PackageJsonContent = @"
{
  "name": "codex-offline-build",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "$PackageName": "$Version",
    "@openai/codex-win32-x64": "npm:$PackageName@$Version-win32-x64"
  }
}
"@

Set-Content -Path $PackageJson -Value $PackageJsonContent -Encoding UTF8
Ok "package.json 已生成（包含 Windows 平台二进制依赖）。"

# ============================================================
# 4. 生成 package-lock.json
# ============================================================

Write-Host ""
Info "[4/9] 生成 package-lock.json..."

Push-Location $CodexAgentDir
try {
    npm install `
        --package-lock-only `
        --ignore-scripts `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {
        throw "生成 package-lock.json 失败。"
    }
} finally {
    Pop-Location
}
Ok "package-lock.json 已生成。"

# ============================================================
# 5. 下载完整 npm 依赖缓存
# ============================================================

Write-Host ""
Info "[5/9] 下载完整 npm 离线依赖缓存到 codex-agent/npm-cache..."

Push-Location $CodexAgentDir
try {
    npm ci `
        --cache $NpmCacheDir `
        --prefer-offline `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {
        throw "npm ci 依赖下载失败。"
    }

    # 显式把 Windows 平台二进制包与主包缓存入 npm-cache
    npm cache add "$PackageName@$Version" --cache $NpmCacheDir
    npm cache add "$PackageName@$Version-win32-x64" --cache $NpmCacheDir
} finally {
    Pop-Location
}
Ok "npm 依赖缓存已完整下载（含 win32-x64 平台二进制）。"

# ============================================================
# 6. 打包 Codex npm package (.tgz)
# ============================================================

Write-Host ""
Info "[6/9] 下载 Codex 安装包与 Windows 二进制包 (.tgz) 到 codex-agent/npm-packages..."

Push-Location $PackageDir
try {
    npm pack "$PackageName@$Version"
    npm pack "$PackageName@$Version-win32-x64"
    if ($LASTEXITCODE -ne 0) {
        throw "npm pack 失败。"
    }
} finally {
    Pop-Location
}

$TgzList = @(Get-ChildItem -Path $PackageDir -Filter "*.tgz" -File)
if ($TgzList.Count -eq 0) {
    throw "未找到生成的 .tgz 安装包。"
}

Ok "Codex npm 包已生成: $($TgzList.Count) 个安装包 ($(($TgzList | ForEach-Object { $_.Name }) -join ', '))"

# 解压出 Windows 核心二进制程序到 codex-agent/bin
$BinDir = Join-Path $CodexAgentDir "bin"
Ensure-Dir $BinDir

$WinTgz = $TgzList | Where-Object { $_.Name -match "win32-x64" } | Select-Object -First 1
if ($WinTgz) {
    Info "正在从 $($WinTgz.Name) 提取 Windows 原生程序 (codex.exe 等)..."
    $TempExtract = Join-Path $WorkRoot "_tmp_extract"
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

    Ok "Windows 核心二进制程序已就绪: $BinDir\codex.exe"
}

# ============================================================
# 7. 清理临时 node_modules
# ============================================================

Write-Host ""
Info "[7/9] 清理临时 node_modules..."

$NodeModules = Join-Path $CodexAgentDir "node_modules"
if (Test-Path $NodeModules) {
    Remove-Item -Path $NodeModules -Recurse -Force
}
Ok "node_modules 已清理。"

# ============================================================
# 8. 真实离线安装测试 (True Offline Test)
# ============================================================

Write-Host ""
Info "[8/9] 执行真实离线安装测试 (npm ci --offline)..."

if (Test-Path $TestDir) {
    Remove-Item -Path $TestDir -Recurse -Force
}
Ensure-Dir $TestDir

Copy-Item -Path $PackageJson -Destination $TestDir
Copy-Item -Path $PackageLock -Destination $TestDir

Push-Location $TestDir
try {
    npm ci `
        --offline `
        --cache $NpmCacheDir `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {
        throw "离线安装测试失败！离线缓存不完整。"
    }
} finally {
    Pop-Location
    if (Test-Path $TestDir) {
        Remove-Item -Path $TestDir -Recurse -Force
    }
}

Ok "真实离线安装测试 PASS！离线缓存 100% 完整。"

# ============================================================
# 9. 生成 Manifest、校验与同步 codex-agent
# ============================================================

Write-Host ""
Info "[9/9] 生成 manifest.json、SHA256 校验和..."

$ShaFile = Join-Path $CodexAgentDir "SHA256SUMS.txt"
if (Test-Path $ShaFile) {
    Remove-Item -Path $ShaFile -Force
}

$FilesToHash = @(
    $PackageJson,
    $PackageLock,
    $VersionFile
)

Get-ChildItem -Path $PackageDir -Recurse -File | ForEach-Object {
    $FilesToHash += $_.FullName
}

foreach ($F in $FilesToHash) {
    if (Test-Path $F) {
        $Hash = Get-FileHash -Path $F -Algorithm SHA256
        $Rel = $F.Substring($CodexAgentDir.Length + 1)
        Add-Content -Path $ShaFile -Value "$($Hash.Hash)  $Rel" -Encoding UTF8
    }
}

$Manifest = @{
    name         = "codex-offline-bundle"
    package      = $PackageName
    version      = $Version
    buildDate    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    nodeVersion  = $NodeVersion
    npmVersion   = $NpmVersion
}

$ManifestJson = $Manifest | ConvertTo-Json -Depth 5
Set-Content -Path (Join-Path $BundleRoot "manifest.json") -Value $ManifestJson -Encoding UTF8
Set-Content -Path (Join-Path $CodexAgentDir "manifest.json") -Value $ManifestJson -Encoding UTF8

# 同步到本地 codex-agent 目录，使脚本目录同级保持整洁与物料保存
Info "同步物料至本地 codex-agent 目录..."
Copy-Item -Path "$CodexAgentDir\*" -Destination $LocalCodexAgentDir -Recurse -Force
Ok "本地物料目录已更新: $LocalCodexAgentDir"

Write-Host ""
Write-Host "============================================================"
Write-Host " BUILD SUCCESS"
Write-Host "============================================================"
Write-Host ""
Write-Host "Codex 版本: $Version"
Write-Host "物料位置: $CodexAgentDir"
Write-Host ""
Write-Host "下一步：运行 02-pack-offline.ps1 打包离线 ZIP。"
Write-Host ""
