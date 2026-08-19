#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$Bundle = Get-ChildItem `
    $ScriptRoot `
    -Directory |
    Where-Object {
        $_.Name -like "Hermes-FULL-Offline-*"
    } |
    Select-Object -First 1

if (-not $Bundle) {
    throw "没有找到 Hermes-FULL-Offline-* 目录。"
}

$Installer = Join-Path `
    $Bundle.FullName `
    "install-offline.ps1"

if (-not (Test-Path $Installer)) {
    throw "Bundle 内不存在 install-offline.ps1"
}

Set-ExecutionPolicy `
    -Scope Process `
    -ExecutionPolicy Bypass `
    -Force

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Installer