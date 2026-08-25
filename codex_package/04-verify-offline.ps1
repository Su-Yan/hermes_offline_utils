#requires -Version 5.1

$ErrorActionPreference = "Stop"

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$Checker = Join-Path $ScriptRoot "deployment\check.ps1"

if (-not (Test-Path $Checker)) {
    $Checker = Join-Path $ScriptRoot "check.ps1"
}

if (-not (Test-Path $Checker)) {
    throw "未找到 check.ps1（查找路径：$ScriptRoot\deployment\check.ps1）"
}

Set-ExecutionPolicy `
    -Scope Process `
    -ExecutionPolicy Bypass `
    -Force

& powershell.exe `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $Checker

exit $LASTEXITCODE
