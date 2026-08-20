#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS_SCRIPT="${SCRIPT_DIR}/build-codex-offline.ps1"

echo
echo "============================================================"
echo " Codex CLI Offline Package Builder"
echo "============================================================"
echo

echo "Project directory:"
echo "  ${SCRIPT_DIR}"
echo

if [[ ! -f "${PS_SCRIPT}" ]]; then
    echo "ERROR: PowerShell build script not found:"
    echo "  ${PS_SCRIPT}"
    exit 1
fi

# ------------------------------------------------------------
# 查找 PowerShell
# ------------------------------------------------------------

if command -v pwsh >/dev/null 2>&1; then

    POWERSHELL="pwsh"

elif command -v powershell.exe >/dev/null 2>&1; then

    POWERSHELL="powershell.exe"

elif command -v powershell >/dev/null 2>&1; then

    POWERSHELL="powershell"

else

    echo "ERROR: PowerShell was not found."
    echo
    echo "Please run this script from Windows Git Bash"
    echo "or install PowerShell."
    exit 1

fi

echo "PowerShell:"
echo "  ${POWERSHELL}"
echo

# ------------------------------------------------------------
# 调用 PowerShell
# ------------------------------------------------------------

"${POWERSHELL}" \
    -NoProfile \
    -ExecutionPolicy Bypass \
    -File "${PS_SCRIPT}"

EXIT_CODE=$?

echo

if [[ ${EXIT_CODE} -ne 0 ]]; then

    echo "============================================================"
    echo " BUILD FAILED"
    echo "============================================================"

    exit ${EXIT_CODE}

fi

echo "============================================================"
echo " BUILD SUCCESS"
echo "============================================================"
echo