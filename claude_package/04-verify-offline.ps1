#requires -Version 5.1

$ErrorActionPreference = "Continue"

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
$ClaudeExe  = Join-Path $BinDir "claude.exe"
$LocalLauncher = Join-Path $ScriptRoot "claude.cmd"

# 注入当前进程 PATH
if ((Test-Path $BinDir) -and ($env:PATH -notlike "*$BinDir*")) {
    $env:PATH = "$BinDir;$env:PATH"
}

try {
    $NpmPrefix = (npm config get prefix 2>$null).Trim()
    if ($NpmPrefix -and ($env:PATH -notlike "*$NpmPrefix*")) {
        $env:PATH = "$NpmPrefix;$env:PATH"
    }
} catch {}

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
    Pass "Node.js (可选，Claude Code 已包含原生独立可执行文件)"
}

# npm
Write-Host ""
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Pass "npm: $(npm -v)"
} else {
    Pass "npm (可选)"
}

# Claude Code CLI
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
    Fail "Claude Code CLI (未找到 claude 命令或可执行程序)"
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
