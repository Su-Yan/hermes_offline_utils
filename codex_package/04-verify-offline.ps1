#requires -Version 5.1

$ErrorActionPreference = "Continue"

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
$CodexExe   = Join-Path $BinDir "codex.exe"
$LocalLauncher = Join-Path $ScriptRoot "codex.cmd"

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

# Codex CLI
Write-Host ""
$TargetExe = $null

if (Test-Path $CodexExe) {
    $TargetExe = $CodexExe
} else {
    $Cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($Cmd) {
        $TargetExe = $Cmd.Source
    } elseif (Test-Path $LocalLauncher) {
        $TargetExe = $LocalLauncher
    }
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
