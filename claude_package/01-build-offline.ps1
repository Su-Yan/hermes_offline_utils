#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Claude-Offline-Bundle"

$ClaudeAgentDir      = Join-Path $BundleRoot "claude-agent"
$LocalClaudeAgentDir = Join-Path $ScriptRoot "claude-agent"

$PackageName    = "@anthropic-ai/claude-code"
$WinPackageName = "@anthropic-ai/claude-code-win32-x64"

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
Write-Host " Claude Code CLI FULL Offline Builder"
Write-Host "============================================================"
Write-Host ""

Ensure-Dir $WorkRoot
Ensure-Dir $BundleRoot
Ensure-Dir $ClaudeAgentDir
Ensure-Dir $LocalClaudeAgentDir

$NpmCacheDir = Join-Path $ClaudeAgentDir "npm-cache"
$PackageDir  = Join-Path $ClaudeAgentDir "npm-packages"
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

# Claude Code 官方要求 Node >= 18
$NodeMajor = [int]($NodeVersion -replace '^v(\d+)\..*$', '$1')
if ($NodeMajor -lt 18) {
    Warn "Claude Code 官方推荐 Node.js >= 18.0.0，当前环境版本为 $NodeVersion，建议升级。"
}

# ============================================================
# 2. 获取 Claude Code 版本
# ============================================================

Write-Host ""
Info "[2/9] 获取 Claude Code 最新版本..."

$Version = npm view $PackageName version
if ([string]::IsNullOrWhiteSpace($Version)) {
    throw "无法获取 $PackageName 的版本号，请检查网络连接。"
}

Ok "Claude Code 目标版本: $Version"

$VersionFile = Join-Path $ClaudeAgentDir "VERSION.txt"
Set-Content -Path $VersionFile -Value $Version -Encoding UTF8

# ============================================================
# 3. 创建 package.json
# ============================================================

Write-Host ""
Info "[3/9] 在 claude-agent 中创建 package.json (包含 Windows 原生二进制依赖)..."

$PackageJson = Join-Path $ClaudeAgentDir "package.json"
$PackageLock = Join-Path $ClaudeAgentDir "package-lock.json"

$PackageJsonContent = @"
{
  "name": "claude-code-offline-build",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "$PackageName": "$Version",
    "$WinPackageName": "$Version"
  }
}
"@

Set-Content -Path $PackageJson -Value $PackageJsonContent -Encoding UTF8
Ok "package.json 已生成（包含主包及 Windows x64 二进制子包）。"

# ============================================================
# 4. 生成 package-lock.json
# ============================================================

Write-Host ""
Info "[4/9] 生成 package-lock.json..."

Push-Location $ClaudeAgentDir
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
Info "[5/9] 下载完整 npm 离线依赖缓存到 claude-agent/npm-cache..."

Push-Location $ClaudeAgentDir
try {
    npm ci `
        --cache $NpmCacheDir `
        --prefer-offline `
        --no-audit `
        --no-fund

    if ($LASTEXITCODE -ne 0) {
        throw "npm ci 依赖下载失败。"
    }

    # 显式把主包与平台原生包缓存入 npm-cache
    npm cache add "$PackageName@$Version" --cache $NpmCacheDir
    npm cache add "$WinPackageName@$Version" --cache $NpmCacheDir
} finally {
    Pop-Location
}
Ok "npm 依赖缓存已完整下载（含 Windows x64 原生二进制）。"

# ============================================================
# 6. 打包 Claude Code npm package (.tgz)
# ============================================================

Write-Host ""
Info "[6/9] 下载 Claude Code 安装包及 Windows 原生二进制包 (.tgz) 到 claude-agent/npm-packages..."

Push-Location $PackageDir
try {
    npm pack "$PackageName@$Version"
    npm pack "$WinPackageName@$Version"
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

Ok "Claude Code npm 包已生成: $($TgzList.Count) 个安装包 ($(($TgzList | ForEach-Object { $_.Name }) -join ', '))"

# 解压出 Windows 核心二进制程序到 claude-agent/bin
$BinDir = Join-Path $ClaudeAgentDir "bin"
Ensure-Dir $BinDir

$WinTgz = $TgzList | Where-Object { $_.Name -match "win32-x64" } | Select-Object -First 1
if ($WinTgz) {
    Info "正在从 $($WinTgz.Name) 提取 Windows 原生程序 (claude.exe)..."
    $TempExtract = Join-Path $WorkRoot "_tmp_extract"
    if (Test-Path $TempExtract) { Remove-Item -Path $TempExtract -Recurse -Force }
    Ensure-Dir $TempExtract

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
        Copy-Item -Path $FoundExe.FullName -Destination (Join-Path $BinDir "claude.exe") -Force
        $SizeMB = [math]::Round($FoundExe.Length / 1MB, 2)
        Ok "Windows 核心原生程序已就绪: $BinDir\claude.exe ($SizeMB MB)"
    } else {
        Warn "未在 $($WinTgz.Name) 中找到 claude.exe"
    }

    if (Test-Path $TempExtract) {
        Remove-Item -Path $TempExtract -Recurse -Force
    }
}

# ============================================================
# 7. 清理临时 node_modules
# ============================================================

Write-Host ""
Info "[7/9] 清理临时 node_modules..."

$NodeModules = Join-Path $ClaudeAgentDir "node_modules"
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
# 9. 生成 Manifest、校验与同步 claude-agent
# ============================================================

Write-Host ""
Info "[9/9] 生成 manifest.json、SHA256 校验和..."

$ShaFile = Join-Path $ClaudeAgentDir "SHA256SUMS.txt"
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

if (Test-Path (Join-Path $BinDir "claude.exe")) {
    $FilesToHash += (Join-Path $BinDir "claude.exe")
}

foreach ($F in $FilesToHash) {
    if (Test-Path $F) {
        $Hash = Get-FileHash -Path $F -Algorithm SHA256
        $Rel = $F.Substring($ClaudeAgentDir.Length + 1)
        Add-Content -Path $ShaFile -Value "$($Hash.Hash)  $Rel" -Encoding UTF8
    }
}

$Manifest = @{
    name         = "claude-code-offline-bundle"
    package      = $PackageName
    version      = $Version
    buildDate    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    nodeVersion  = $NodeVersion
    npmVersion   = $NpmVersion
}

$ManifestJson = $Manifest | ConvertTo-Json -Depth 5
Set-Content -Path (Join-Path $BundleRoot "manifest.json") -Value $ManifestJson -Encoding UTF8
Set-Content -Path (Join-Path $ClaudeAgentDir "manifest.json") -Value $ManifestJson -Encoding UTF8

# 同步到本地 claude-agent 目录，使脚本目录同级保持整洁与物料保存
Info "同步物料至本地 claude-agent 目录..."
Copy-Item -Path "$ClaudeAgentDir\*" -Destination $LocalClaudeAgentDir -Recurse -Force
Ok "本地物料目录已更新: $LocalClaudeAgentDir"

Write-Host ""
Write-Host "============================================================"
Write-Host " BUILD SUCCESS"
Write-Host "============================================================"
Write-Host ""
Write-Host "Claude Code 版本: $Version"
Write-Host "物料位置: $ClaudeAgentDir"
Write-Host ""
Write-Host "下一步：运行 02-pack-offline.ps1 打包离线 ZIP。"
Write-Host ""
