#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 脚本在 utils\ 内，bundle 根目录是上一级
$BundleRoot = Split-Path -Parent $ScriptRoot

$Installer = Join-Path $BundleRoot "install-offline.ps1"

if (-not (Test-Path $Installer)) {
    throw "Bundle 内不存在 install-offline.ps1（查找路径：$Installer）"
}

Set-ExecutionPolicy `
    -Scope Process `
    -ExecutionPolicy Bypass `
    -Force

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Installer