#requires -Version 5.1

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$WorkRoot   = Join-Path $ScriptRoot "_build"
$BundleRoot = Join-Path $WorkRoot "Hermes-Offline-Bundle"

$RepoDir    = Join-Path $BundleRoot "hermes-agent"
$RuntimeDir = Join-Path $BundleRoot "runtime"
$ToolsDir   = Join-Path $BundleRoot "tools"
$CacheDir   = Join-Path $BundleRoot "cache"

$NodeDir        = Join-Path $RuntimeDir "node"
$GitDir         = Join-Path $RuntimeDir "git"
$PythonDir      = Join-Path $RuntimeDir "python"
$PlaywrightDir  = Join-Path $RuntimeDir "playwright-browsers"
$AgentBrowserDir = Join-Path $RuntimeDir "agent-browser"

$RepoUrl = "https://github.com/NousResearch/hermes-agent.git"

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

function Copy-Dir($Source, $Destination) {
    if (-not (Test-Path $Source)) {
        return
    }

    Ensure-Dir $Destination

    robocopy `
        $Source `
        $Destination `
        /E `
        /R:2 `
        /W:1 `
        /NFL `
        /NDL `
        /NJH `
        /NJS `
        /NP | Out-Null
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Hermes Agent FULL Offline Builder"
Write-Host "============================================================"
Write-Host ""

Ensure-Dir $WorkRoot
Ensure-Dir $BundleRoot
Ensure-Dir $RuntimeDir
Ensure-Dir $ToolsDir
Ensure-Dir $CacheDir

# ============================================================
# 1. 基础工具
# ============================================================

Info "检查构建机..."

Require-Command git
Require-Command node
Require-Command npm

$NodeVersion = node --version
$NpmVersion  = npm --version

Info "Node : $NodeVersion"
Info "npm  : $NpmVersion"

if (-not ($NodeVersion -match "^v(20|22)\.")) {
    throw "Hermes 当前要求 Node >=20，推荐 Node 22。当前：$NodeVersion"
}

# ============================================================
# 2. Hermes main
# ============================================================

Info "获取 Hermes main..."

# 同级目录的本地仓库（优先使用，避免联网）
$LocalRepoDir = Join-Path $ScriptRoot "hermes-agent"

if (Test-Path (Join-Path $RepoDir ".git")) {

    # 构建目录已有副本，直接更新
    Push-Location $RepoDir

    git fetch origin main
    git checkout main
    git reset --hard origin/main

    Pop-Location

} elseif (Test-Path (Join-Path $LocalRepoDir ".git")) {

    # 同级目录已有本地仓库，从本地克隆（无需联网，不含 venv/node_modules）
    Info "发现本地 hermes-agent，从本地克隆到构建目录..."

    if (Test-Path $RepoDir) {
        Remove-Item $RepoDir -Recurse -Force
    }

    git clone --branch main $LocalRepoDir $RepoDir

    Ok "本地克隆完成。"

} else {

    # 本地没有，从 GitHub 克隆
    if (Test-Path $RepoDir) {
        Remove-Item $RepoDir -Recurse -Force
    }

    git clone --branch main $RepoUrl $RepoDir
}

Push-Location $RepoDir

$Commit = (git rev-parse HEAD).Trim()
$Branch = (git branch --show-current).Trim()

Pop-Location

Ok "Hermes branch: $Branch"
Ok "Hermes commit: $Commit"

# ============================================================
# 3. uv
# ============================================================

Info "准备 uv..."

$UvCommand = Get-Command uv -ErrorAction SilentlyContinue

if (-not $UvCommand) {

    $UvInstaller = Join-Path $CacheDir "uv-install.ps1"

    if (-not (Test-Path $UvInstaller)) {

        Invoke-WebRequest `
            -Uri "https://astral.sh/uv/install.ps1" `
            -OutFile $UvInstaller `
            -UseBasicParsing
    }

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $UvInstaller

    # 安装后把常见 bin 目录加入当前会话 PATH，让 Get-Command 立即可见
    $UvBinDirs = @(
        "$env:USERPROFILE\.local\bin",
        "$env:USERPROFILE\.cargo\bin"
    )
    foreach ($d in $UvBinDirs) {
        if ((Test-Path $d) -and ($env:PATH -notlike "*$d*")) {
            $env:PATH = "$d;$env:PATH"
        }
    }
}

$UvCommand = Get-Command uv -ErrorAction SilentlyContinue

if (-not $UvCommand) {

    $Candidates = @(
        "$env:USERPROFILE\.local\bin\uv.exe",
        "$env:USERPROFILE\.cargo\bin\uv.exe"
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            # 用 Get-Command 而非 Get-Item，确保返回 ApplicationInfo（有 .Source 属性）
            $UvCommand = Get-Command $Candidate -ErrorAction SilentlyContinue
            break
        }
    }
}

if (-not $UvCommand) {
    throw "uv 安装失败。"
}

$Uv = $UvCommand.Source

Ok "uv: $Uv"

# ============================================================
# 4. Python 3.11
# ============================================================

Info "准备 Python 3.11..."

& $Uv python install 3.11

if ($LASTEXITCODE -ne 0) {
    throw "Python 3.11 安装失败。"
}

$VenvDir = Join-Path $RepoDir "venv"

if (Test-Path $VenvDir) {
    Remove-Item $VenvDir -Recurse -Force
}

& $Uv venv `
    $VenvDir `
    --python 3.11

if ($LASTEXITCODE -ne 0) {
    throw "Python venv 创建失败。"
}

$PythonExe = Join-Path $VenvDir "Scripts\python.exe"
$HermesExe = Join-Path $VenvDir "Scripts\hermes.exe"

# ============================================================
# 5. Hermes Python dependencies
# ============================================================

Info "安装 Hermes Python dependencies..."

Push-Location $RepoDir

& $Uv pip install `
    --python $PythonExe `
    -e ".[all]"

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Hermes Python dependencies 安装失败。"
}

Pop-Location

Ok "Python dependencies 完成。"

# ============================================================
# 5b. pip wheels（供内网离线重建 venv）
# ============================================================

Info "下载 pip wheels 缓存（供内网无网络重建 venv）..."

$PipWheelsDir = Join-Path $CacheDir "pip-wheels"
Ensure-Dir $PipWheelsDir

# uv venv 默认不含 pip，先通过 uv 装入
Info "在 venv 中安装 pip..."
& $Uv pip install --python $PythonExe pip

if ($LASTEXITCODE -ne 0) {
    throw "pip 安装到 venv 失败。"
}

# uv pip freeze 不依赖 pip 本身，可直接列出所有已装包（排除 editable 的 hermes）
$FreezeFile = Join-Path $CacheDir "requirements-freeze.txt"

& $Uv pip freeze --python $PythonExe --exclude-editable |
    Set-Content $FreezeFile -Encoding UTF8

Info "requirements-freeze.txt 已生成：$FreezeFile"

# 用 pip download 把全部依赖下载为 wheel 文件
& $PythonExe -m pip download `
    --dest $PipWheelsDir `
    --requirement $FreezeFile

if ($LASTEXITCODE -ne 0) {
    throw "pip wheels 下载失败。"
}

Ok "pip wheels 已缓存：$PipWheelsDir"

# ============================================================
# 6. Node workspace
# ============================================================

Info "安装 Hermes Node workspace..."

Push-Location $RepoDir

if (Test-Path "package-lock.json") {
    npm ci
}
else {
    npm install
}

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "npm install 失败。"
}

Pop-Location

# ============================================================
# 7. agent-browser
# ============================================================

Info "安装 agent-browser..."

Ensure-Dir $AgentBrowserDir

Push-Location $AgentBrowserDir

npm init -y --silent

npm install agent-browser --ignore-scripts

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "agent-browser npm 安装失败。"
}

Pop-Location

$AgentBrowserBin = Join-Path `
    $AgentBrowserDir `
    "node_modules\.bin\agent-browser.cmd"

if (-not (Test-Path $AgentBrowserBin)) {
    throw "agent-browser.cmd 不存在：$AgentBrowserBin"
}

Ok "agent-browser package 已安装。"

# ============================================================
# 8. agent-browser 自检
# ============================================================

Info "测试 agent-browser..."

$OldPath = $env:PATH

$env:PATH = `
    "$(Join-Path $AgentBrowserDir 'node_modules\.bin');$env:PATH"

& $AgentBrowserBin --version

if ($LASTEXITCODE -ne 0) {
    $env:PATH = $OldPath
    throw "agent-browser --version 失败。"
}

$env:PATH = $OldPath

Ok "agent-browser 可执行。"

# ============================================================
# 9. Playwright Chromium
# ============================================================

Info "安装 Playwright Chromium..."

Ensure-Dir $PlaywrightDir

$env:PLAYWRIGHT_BROWSERS_PATH = $PlaywrightDir

Push-Location $AgentBrowserDir

$npx = Get-Command npx -ErrorAction SilentlyContinue

if (-not $npx) {
    Pop-Location
    throw "找不到 npx。"
}

npx playwright install chromium

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
    throw "Playwright Chromium 安装失败。"
}

Pop-Location

Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue

# 验证浏览器目录
$ChromiumFiles = Get-ChildItem `
    $PlaywrightDir `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue

if ($ChromiumFiles.Count -eq 0) {
    throw "Playwright Chromium 没有产生任何文件。"
}

Ok "Playwright Chromium 已缓存。"

# ============================================================
# 10. ffmpeg
# ============================================================

Info "准备 ffmpeg..."

$FfmpegDir = Join-Path $ToolsDir "ffmpeg"

Ensure-Dir $FfmpegDir

# 优先使用系统已有 ffmpeg
$FfmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue

if ($FfmpegCommand) {

    Copy-Item `
        $FfmpegCommand.Source `
        (Join-Path $FfmpegDir "ffmpeg.exe") `
        -Force

}
else {

    Warn "构建机没有 ffmpeg。"

    Write-Host ""
    Write-Host "请先在外网构建机安装 ffmpeg，然后重新运行本脚本。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "例如使用 winget：" -ForegroundColor Yellow
    Write-Host "    winget install Gyan.FFmpeg.Shared"
    Write-Host ""

    throw "缺少 ffmpeg.exe。"
}

& (Join-Path $FfmpegDir "ffmpeg.exe") -version | Select-Object -First 1

Ok "ffmpeg 已打包。"

# ============================================================
# 11. ripgrep
# ============================================================

Info "准备 ripgrep..."

$RgDir = Join-Path $ToolsDir "ripgrep"

Ensure-Dir $RgDir

$RgCommand = Get-Command rg -ErrorAction SilentlyContinue

if ($RgCommand) {

    Copy-Item `
        $RgCommand.Source `
        (Join-Path $RgDir "rg.exe") `
        -Force

}
else {

    Warn "构建机没有 ripgrep。"

    Write-Host ""
    Write-Host "请先在外网构建机安装 ripgrep，然后重新运行本脚本。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "例如使用 winget：" -ForegroundColor Yellow
    Write-Host "    winget install BurntSushi.ripgrep.MSVC"
    Write-Host ""

    throw "缺少 rg.exe。"
}

& (Join-Path $RgDir "rg.exe") --version

Ok "ripgrep 已打包。"

# ============================================================
# 12. Node runtime
# ============================================================

Info "收集 Node runtime..."

$NodeExe = (Get-Command node).Source
$NodeHome = Split-Path $NodeExe -Parent

if (Test-Path $NodeDir) {
    Remove-Item $NodeDir -Recurse -Force
}

Copy-Dir $NodeHome $NodeDir

Ok "Node runtime 完成。"

# ============================================================
# 13. Git runtime
# ============================================================

Info "收集 Git / Git Bash..."

$GitExe = (Get-Command git).Source
$GitBin = Split-Path $GitExe -Parent
$GitHome = Split-Path $GitBin -Parent

# git.exe 有时在 mingw64\bin\ 或 mingw32\bin\ 子目录里，
# 需要再上推一级才是真正的 Git 安装根目录
if ((Split-Path $GitHome -Leaf) -match '^mingw') {
    $GitHome = Split-Path $GitHome -Parent
}

if (Test-Path $GitDir) {
    Remove-Item $GitDir -Recurse -Force
}

Copy-Dir $GitHome $GitDir

# bash.exe 在不同安装方式下可能位于不同子目录，依次尝试
$BashRelPaths = @(
    "bin\bash.exe",
    "usr\bin\bash.exe",
    "mingw64\bin\bash.exe",
    "mingw32\bin\bash.exe"
)

$GitBash = $null

foreach ($Rel in $BashRelPaths) {
    $Candidate = Join-Path $GitDir $Rel
    if (Test-Path $Candidate) {
        $GitBash = $Candidate
        break
    }
}

if (-not $GitBash) {
    throw "Git bundle 中找不到 bash.exe，已检查：$($BashRelPaths -join ', ')"
}

Ok "Git Bash: $GitBash"


# ============================================================
# 14. Python runtime
# ============================================================

Info "收集 Python runtime..."

$PythonHome = (& $Uv python find 3.11).Trim()

if (-not $PythonHome) {
    throw "无法获取 Python runtime 路径。"
}

if (Test-Path $PythonDir) {
    Remove-Item $PythonDir -Recurse -Force
}

Copy-Dir $PythonHome $PythonDir

Ok "Python runtime 完成。"

# ============================================================
# 15. Electron caches
# ============================================================

Info "收集 Electron caches..."

$ElectronCacheRoot = Join-Path $RuntimeDir "electron-cache"

Ensure-Dir $ElectronCacheRoot

$ElectronCacheCandidates = @(
    "$env:LOCALAPPDATA\electron\Cache",
    "$env:LOCALAPPDATA\electron-builder\Cache",
    "$env:APPDATA\electron\Cache",
    "$env:USERPROFILE\.cache\electron",
    "$env:USERPROFILE\.cache\electron-builder"
)

$FoundElectronCache = $false

foreach ($Candidate in $ElectronCacheCandidates) {

    if (Test-Path $Candidate) {

        $Name = Split-Path $Candidate -Leaf

        if ([string]::IsNullOrWhiteSpace($Name)) {
            $Name = "cache"
        }

        $Destination = Join-Path `
            $ElectronCacheRoot `
            $Name

        Copy-Dir $Candidate $Destination

        $FoundElectronCache = $true

        Ok "Electron cache: $Candidate"
    }
}

if (-not $FoundElectronCache) {
    Warn "没有发现 Electron cache。"

    Write-Host ""
    Write-Host "如果 Desktop 已成功 npm run dist:win，通常应该至少产生 Electron/electron-builder cache。" -ForegroundColor Yellow
}

# ============================================================
# 16. npm cache
# ============================================================

Info "收集 npm cache..."

$NpmCache = npm config get cache

if ($NpmCache -and (Test-Path $NpmCache)) {

    Copy-Dir `
        $NpmCache `
        (Join-Path $CacheDir "npm")

    Ok "npm cache 完成。"
}

# ============================================================
# 17. Desktop build
# ============================================================

Info "构建 Hermes Desktop Windows..."

Push-Location $RepoDir

npm run dist:win --workspace apps/desktop

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    throw "Desktop Windows build 失败。"
}

Pop-Location

$ReleaseDir = Join-Path `
    $RepoDir `
    "apps\desktop\release"

if (-not (Test-Path $ReleaseDir)) {
    throw "Desktop release 不存在。"
}

$ReleaseFiles = Get-ChildItem `
    $ReleaseDir `
    -Recurse `
    -File

if ($ReleaseFiles.Count -eq 0) {
    throw "Desktop release 是空目录。"
}

Ok "Desktop build 完成。"

# ============================================================
# 18. 重新检查 Chromium
# ============================================================

if (-not (Test-Path $PlaywrightDir)) {
    throw "Playwright browser cache 不存在。"
}

# ============================================================
# 19. Manifest
# ============================================================

$PythonVersion = & $PythonExe --version
$GitVersion    = git --version

$FfmpegVersion = `
    & (Join-Path $FfmpegDir "ffmpeg.exe") -version 2>&1 |
    Select-Object -First 1

$RgVersion = `
    & (Join-Path $RgDir "rg.exe") --version |
    Select-Object -First 1

$AgentBrowserVersion = `
    & $AgentBrowserBin --version

$Manifest = [ordered]@{
    product = "Hermes Agent"
    branch = $Branch
    commit = $Commit
    builtAt = (Get-Date).ToString("o")
    architecture = $env:PROCESSOR_ARCHITECTURE

    python = "$PythonVersion"
    node = "$NodeVersion"
    npm = "$NpmVersion"
    git = "$GitVersion"

    ffmpeg = "$FfmpegVersion"
    ripgrep = "$RgVersion"
    agentBrowser = "$AgentBrowserVersion"

    playwrightBrowsers = $PlaywrightDir
    electronCacheIncluded = $FoundElectronCache

    desktopRelease = $ReleaseDir
}

$Manifest |
    ConvertTo-Json -Depth 10 |
    Set-Content `
        -Encoding UTF8 `
        (Join-Path $BundleRoot "manifest.json")

# ============================================================
# 20. 环境文件
# ============================================================

$Environment = [ordered]@{
    HERMES_HOME = "%LOCALAPPDATA%\hermes"

    HERMES_GIT_BASH_PATH =
        "%~dp0runtime\git\bin\bash.exe"

    PLAYWRIGHT_BROWSERS_PATH =
        "%~dp0runtime\playwright-browsers"

    HERMES_AGENT_BROWSER_ROOT =
        "%~dp0runtime\agent-browser"

    HERMES_FFMPEG =
        "%~dp0tools\ffmpeg\ffmpeg.exe"

    HERMES_RIPGREP =
        "%~dp0tools\ripgrep\rg.exe"
}

$Environment |
    ConvertTo-Json |
    Set-Content `
        -Encoding UTF8 `
        (Join-Path $BundleRoot "environment.json")

# ============================================================
# 21. 完成
# ============================================================

Write-Host ""
Write-Host "============================================================"
Write-Host " FULL OFFLINE BUILD SUCCESS"
Write-Host "============================================================"
Write-Host ""

Write-Host "Hermes commit:"
Write-Host $Commit

Write-Host ""
Write-Host "Browser:"
Write-Host "    agent-browser : OK"
Write-Host "    Chromium      : OK"

Write-Host ""
Write-Host "System tools:"
Write-Host "    ffmpeg        : OK"
Write-Host "    ripgrep       : OK"

Write-Host ""
Write-Host "Desktop:"
Write-Host "    release       : OK"

Write-Host ""
Write-Host "下一步："
Write-Host "    .\02-pack-offline.ps1"
Write-Host ""

Read-Host "按 Enter 退出"