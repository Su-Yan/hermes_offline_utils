#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# 优先在当前目录找 deployment/install.ps1，否则检查当前目录直接的 install.ps1
$Installer = Join-Path $ScriptRoot "deployment\install.ps1"

if (-not (Test-Path $Installer)) {
    $Installer = Join-Path $ScriptRoot "install.ps1"
}

if (-not (Test-Path $Installer)) {
    throw "未找到 install.ps1（查找路径：$ScriptRoot\deployment\install.ps1）"
}

Set-ExecutionPolicy `
    -Scope Process `
    -ExecutionPolicy Bypass `
    -Force

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Installer

exit $LASTEXITCODE
