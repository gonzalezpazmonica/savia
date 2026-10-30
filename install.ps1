# install.ps1 — One-line installer for PM-Workspace (Savia) on Windows with OpenCode
# Usage: irm https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.ps1 | iex
#
# ⚠️  SECURITY WARNING: This script is piped directly to PowerShell execution (irm|iex).
#     Always verify the source before execution. Only run from official GitHub releases:
#     https://github.com/gonzalezpazmonica/pm-workspace/releases
#     Do NOT run from untrusted or modified URLs.
#
# Environment variables:
#   SAVIA_HOME    — Installation directory (default: ~\savia)
#   SKIP_TESTS    — Set to 1 to skip smoke tests

$ErrorActionPreference = "Stop"

# --- Helpers -------------------------------------------------------------------
function Write-Info  { param($msg) Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Fail  { param($msg) Write-Host "  $msg" -ForegroundColor Red }
function Write-Step  { param($num, $msg) Write-Host "`n[$num/7] $msg" -ForegroundColor White }

# --- Help ----------------------------------------------------------------------
if ($args -contains "--help" -or $args -contains "-h") {
    Write-Host "PM-Workspace (Savia) Installer for Windows"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  irm https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.ps1 | iex"
    Write-Host "  .\install.ps1 [--skip-tests] [--help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --skip-tests    Skip smoke tests after installation"
    Write-Host "  --help, -h      Show this help message"
    Write-Host ""
    Write-Host "Environment variables:"
    Write-Host "  SAVIA_HOME      Installation directory (default: ~\savia)"
    Write-Host "  SKIP_TESTS      Set to 1 to skip smoke tests"
    Write-Host ""
    Write-Host "Exit codes: 0 Success, 1 Missing prereqs, 2 Network error, 3 Cancelled"
    exit 0
}

$SkipTests = ($args -contains "--skip-tests") -or ($env:SKIP_TESTS -eq "1")

# --- Banner -------------------------------------------------------------------
Write-Host @"

    ,___,        ____              _
    (O,O)       / ___|  __ ___   _(_) __ _
    /)  )      \___ \ / _`` \ \ / / |/ _`` |
   ( (_ \       ___) | (_| |\ V /| | (_| |
    ``----'     |____/ \__,_| \_/ |_|\__,_|

    PM-Workspace  -  One-Line Installer (Windows)

"@ -ForegroundColor White

# --- Step 1: Detect environment ------------------------------------------------
Write-Step 1 "Detecting environment..."

$Arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
$WinVer = [System.Environment]::OSVersion.Version
Write-Ok "Windows $($WinVer.Major).$($WinVer.Minor) ($Arch)"

# Detect WSL
$HasWSL = $false
try {
    $wslCheck = wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) { $HasWSL = $true }
} catch { }

if ($HasWSL) {
    Write-Info "WSL detected. Tip: you can also run install.sh directly inside WSL."
}

# --- Step 2: Check prerequisites -----------------------------------------------
Write-Step 2 "Checking prerequisites..."

$Missing = 0

# Helper: detect package manager
$HasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
$HasChoco  = $null -ne (Get-Command choco -ErrorAction SilentlyContinue)

function Install-Pkg {
    param($wingetId, $chocoId, $label, $url)
    if ($HasWinget) {
        Write-Info "Installing $label via winget..."
        winget install --id $wingetId --accept-source-agreements --accept-package-agreements --silent 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    if ($HasChoco) {
        Write-Info "Installing $label via choco..."
        choco install $chocoId -y 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    Write-Fail "$label could not be installed automatically. Install manually from: $url"
    return $false
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

# Git
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $gitVer = (git --version) -replace 'git version ', ''
    Write-Ok "Git $gitVer"
} else {
    if (Install-Pkg 'Git.Git' 'git' 'Git' 'https://git-scm.com') {
        Refresh-Path
        Write-Ok "Git installed"
    } else { $Missing = 1 }
}

# Node.js
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
$needNode = $false
if ($nodeCmd) {
    $nodeVer = (node --version) -replace 'v', ''
    $nodeMajor = [int]($nodeVer.Split('.')[0])
    if ($nodeMajor -ge 18) {
        Write-Ok "Node.js v$nodeVer"
    } else {
        Write-Warn "Node.js v$nodeVer is too old (need >= 18). Upgrading..."
        $needNode = $true
    }
} else {
    $needNode = $true
}
if ($needNode) {
    if (Install-Pkg 'OpenJS.NodeJS.LTS' 'nodejs-lts' 'Node.js LTS' 'https://nodejs.org') {
        Refresh-Path
        $nodeVer = try { (node --version) -replace 'v', '' } catch { "unknown" }
        Write-Ok "Node.js v$nodeVer installed"
    } else { $Missing = 1 }
}

# Python 3 (optional) - Windows has a python3.exe stub that redirects to Store
$pyCmd = $null
foreach ($pyName in @('python3', 'python')) {
    $candidate = Get-Command $pyName -ErrorAction SilentlyContinue
    if ($candidate) {
        try {
            $pyOut = & $candidate.Source --version 2>&1
            if ($pyOut -match 'Python \d') {
                $pyCmd = $candidate
                break
            }
        } catch { }
    }
}
if ($pyCmd) {
    $pyVer = ($pyOut) -replace 'Python ', ''
    Write-Ok "Python $pyVer"
} else {
    Write-Warn "Python not found. Attempting install..."
    if (Install-Pkg 'Python.Python.3.12' 'python3' 'Python 3' 'https://python.org') {
        Refresh-Path
        Write-Ok "Python installed"
    } else {
        Write-Warn 'Python not available (optional - needed for capacity calculator)'
    }
}

# jq (optional)
$jqCmd = Get-Command jq -ErrorAction SilentlyContinue
if ($jqCmd) {
    Write-Ok "jq found"
} else {
    Write-Info "Installing jq..."
    if (-not (Install-Pkg 'jqlang.jq' 'jq' 'jq' 'https://jqlang.github.io/jq/')) {
        Write-Warn 'jq not available (optional)'
    } else {
        Refresh-Path
        Write-Ok "jq installed"
    }
}

if ($Missing -eq 1) {
    Write-Host ""
    Write-Fail "Could not install required prerequisites. Install Git and Node.js manually and re-run."
    exit 1
}

# Git Bash: Claude Code runs every bash hook through Git for Windows' bash.exe.
# Without it, PreToolUse hooks time out and block even reads ("Git Bash wasn't found").
function Find-GitBash {
    $candidates = @()
    if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $candidates += $env:CLAUDE_CODE_GIT_BASH_PATH }
    if ($env:ProgramFiles)           { $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
    if (${env:ProgramFiles(x86)})    { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe') }
    if ($env:LOCALAPPDATA)           { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    $gc = Get-Command git -ErrorAction SilentlyContinue
    if ($gc) {
        # <root>\cmd\git.exe -> <root>\bin\bash.exe (never the WSL bash.exe in System32)
        $candidates += (Join-Path (Split-Path (Split-Path $gc.Source)) 'bin\bash.exe')
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

$GitBashPath = Find-GitBash
if (-not $GitBashPath) {
    Write-Host ""
    Write-Fail "Git Bash (bash.exe) not found. Claude Code needs it to run Savia's hooks."
    Write-Fail "Install Git for Windows (includes Git Bash): https://git-scm.com/downloads/win"
    Write-Fail "Then re-run this installer, or set CLAUDE_CODE_GIT_BASH_PATH to your bash.exe."
    exit 1
}
Write-Ok "Git Bash: $GitBashPath"

# Claude Code finds bash.exe from git.exe on PATH. If that route does not lead to the
# bash we found (git not on PATH, non-standard install), pin it for the user.
$gcmd = Get-Command git -ErrorAction SilentlyContinue
$viaGit = if ($gcmd) { Join-Path (Split-Path (Split-Path $gcmd.Source)) 'bin\bash.exe' }
$bashOnPath = $viaGit -and (Test-Path $viaGit) -and ($viaGit -eq $GitBashPath)
if (-not $bashOnPath -and $env:CLAUDE_CODE_GIT_BASH_PATH -ne $GitBashPath) {
    [Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH', $GitBashPath, 'User')
    $env:CLAUDE_CODE_GIT_BASH_PATH = $GitBashPath
    Write-Ok "CLAUDE_CODE_GIT_BASH_PATH set (user) to $GitBashPath"
    Write-Warn "Open a NEW terminal before starting Claude Code so it picks up the variable."
}

# --- Step 3: OpenCode ----------------------------------------------------------
Write-Step 3 "Checking OpenCode..."

if (Get-Command opencode -ErrorAction SilentlyContinue) {
    $ocVer = try { opencode --version 2>&1 | Select-Object -First 1 } catch { "found" }
    Write-Ok "OpenCode already installed ($ocVer)"
} else {
    # @opencode/cli = OpenCode 2 (recommended), opencode-ai = OpenCode 1 (>= 1.18.29 for the Savia plugins).
    # @opencode-ai/cli is NOT OpenCode. Choose with SAVIA_OPENCODE_FLAVOR=v1|v2 (default v2).
    $ocPkg = if ($env:SAVIA_OPENCODE_FLAVOR -eq "v1") { "opencode-ai" } else { "@opencode/cli" }
    Write-Info "OpenCode not found - installing $ocPkg..."
    try {
        npm install -g $ocPkg 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "OpenCode installed via npm"
        } else {
            throw "npm install failed"
        }
    } catch {
        Write-Warn "OpenCode installation failed. Install it later:"
        Write-Host "    npm install -g @opencode/cli   # OpenCode 2 (recommended)"
        Write-Host "    npm install -g opencode-ai     # OpenCode 1"
    }
}

# --- Step 4: Clone PM-Workspace ------------------------------------------------
Write-Step 4 "Setting up PM-Workspace..."

$SaviaHome = if ($env:SAVIA_HOME) { $env:SAVIA_HOME } else { Join-Path $HOME "savia" }
$RepoUrl = "https://github.com/gonzalezpazmonica/pm-workspace.git"

# Detect if running from inside the repo already
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RunningFromRepo = Test-Path (Join-Path $ScriptDir "CLAUDE.md")

if ($RunningFromRepo) {
    # Already inside the repo — use this directory
    $SaviaHome = $ScriptDir
    Write-Ok "Using current directory: $SaviaHome"
} elseif (Test-Path (Join-Path $SaviaHome ".git")) {
    Write-Info "Directory $SaviaHome already exists."
    $reply = Read-Host "    Update (git pull)? [Y/n/abort]"
    switch -Regex ($reply.ToLower()) {
        "^n"     { Write-Ok "Skipping - using existing installation" }
        "^abort" { Write-Info "Installation cancelled."; exit 3 }
        default  {
            try {
                git -C $SaviaHome pull --ff-only origin main 2>&1 | Out-Null
                Write-Ok "Updated to latest version"
            } catch {
                Write-Warn "Pull failed - continuing with existing version"
            }
        }
    }
} elseif (Test-Path $SaviaHome) {
    # ~/savia exists but is not a git repo
    $SaviaHome = Join-Path $HOME "pm-workspace"
    Write-Info "$HOME\savia exists but is not pm-workspace. Using $SaviaHome instead..."
    if (Test-Path (Join-Path $SaviaHome ".git")) {
        Write-Ok "Found existing pm-workspace at $SaviaHome"
    } else {
        Write-Info "Cloning pm-workspace to $SaviaHome..."
        $cloneOutput = git clone $RepoUrl $SaviaHome 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "Clone failed: $cloneOutput"
            exit 2
        }
        Write-Ok "Cloned to $SaviaHome"
    }
} else {
    Write-Info "Cloning pm-workspace to $SaviaHome..."
    $cloneOutput = git clone $RepoUrl $SaviaHome 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Clone failed: $cloneOutput"
        exit 2
    }
    Write-Ok "Cloned to $SaviaHome"
}

# Git for Windows checks symlinks out as text files (core.symlinks=false):
# materialize them as junctions/hard links. Git Bash, never WSL bash.
$gitBash = $GitBashPath
if ($gitBash -and (Test-Path $gitBash)) {
    Push-Location $SaviaHome
    try {
        & $gitBash scripts/windows-links.sh repair --quiet
        if ($LASTEXITCODE -eq 0) { Write-Ok "Repository links materialized" }
        else { Write-Warn 'Some repository links need review: bash scripts/windows-links.sh check' }
    } finally { Pop-Location }
} else {
    Write-Warn 'Git Bash not found - run later: bash scripts/windows-links.sh repair'
}

# --- Step 5: Install dependencies -----------------------------------------------
Write-Step 5 "Installing script dependencies..."

$pkgJson = Join-Path $SaviaHome "scripts\package.json"
if (Test-Path $pkgJson) {
    try {
        Push-Location (Join-Path $SaviaHome "scripts")
        npm install --silent 2>&1 | Out-Null
        Pop-Location
        Write-Ok "npm dependencies installed"
    } catch {
        Pop-Location
        Write-Warn "npm install had warnings (non-critical)"
    }
} else {
    Write-Warn "No package.json found in scripts\ - skipping npm install"
}

# --- Step 6: Savia Bridge Setup -----------------------------------------------
Write-Step 6 "Setting up Savia Bridge..."

# Check if Python is available
$PyCmd = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $PyCmd) { $PyCmd = Get-Command python -ErrorAction SilentlyContinue }

if ($PyCmd) {
    $PythonPath = $PyCmd.Source

    # Create bridge directories
    $BridgeScriptDir = Join-Path $env:USERPROFILE ".savia\scripts"
    $BridgeDir = Join-Path $env:USERPROFILE ".savia\bridge"
    $BridgeApkDir = Join-Path $BridgeDir "apk"

    New-Item -ItemType Directory -Force -Path $BridgeScriptDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null
    New-Item -ItemType Directory -Force -Path $BridgeApkDir | Out-Null
    Write-Ok "Bridge directories created"

    # Copy savia-bridge.py script
    $SourceScript = Join-Path $SaviaHome "scripts\savia-bridge.py"
    if (Test-Path $SourceScript) {
        Copy-Item $SourceScript (Join-Path $BridgeScriptDir "savia-bridge.py") -Force
        Write-Ok "Bridge script copied"
    } else {
        Write-Warn "savia-bridge.py not found in scripts - skipping"
    }

    # Generate random auth token using Python
    try {
        $AuthToken = & $PythonPath -c "import secrets; print(secrets.token_hex(32))" 2>$null
    } catch {
        Write-Warn "Failed to generate token with Python - using random GUID"
        $AuthToken = [guid]::NewGuid().ToString() -replace "-",""
    }

    # Create config file
    $ConfigPath = Join-Path $BridgeDir "config.json"
    $ConfigContent = @"
{
  "host": "0.0.0.0",
  "port": 8922,
  "token": "$AuthToken"
}
"@
    Set-Content -Path $ConfigPath -Value $ConfigContent
    Write-Ok "Bridge config created at $ConfigPath"

    # Windows: Create scheduled task or batch file for auto-start
    $BridgeStartDir = Join-Path $env:APPDATA "Savia\startup"
    New-Item -ItemType Directory -Force -Path $BridgeStartDir | Out-Null

    # Create batch file to run bridge on startup
    $BatchPath = Join-Path $BridgeStartDir "start-bridge.bat"
    $BatchContent = @"
@echo off
pushd "%USERPROFILE%\.savia\scripts"
python savia-bridge.py
popd
"@
    Set-Content -Path $BatchPath -Value $BatchContent -Encoding ASCII
    Write-Ok "Bridge startup script created at $BatchPath"

    # Add to Windows Startup folder (user startup)
    $StartupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path $StartupFolder) {
        # Create shortcut to batch file
        $WshShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WshShell.CreateShortcut((Join-Path $StartupFolder "Savia Bridge.lnk"))
        $Shortcut.TargetPath = $BatchPath
        $Shortcut.WorkingDirectory = (Join-Path $env:USERPROFILE ".savia\scripts")
        $Shortcut.Save()
        Write-Ok "Bridge added to Windows Startup"
    }

    # Display setup information
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Yellow
    Write-Host "  Bridge Auth Token" -ForegroundColor Yellow
    Write-Host "==============================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Copy this token to configure the mobile app:" -ForegroundColor White
    Write-Host "$AuthToken" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host ""
    Write-Host "Token saved in: $ConfigPath" -ForegroundColor White
    Write-Host ""
    Write-Host "Startup:" -ForegroundColor White
    Write-Host "  - Batch file: $BatchPath" -ForegroundColor White
    Write-Host "  - Startup folder: Added (will auto-run on next login)" -ForegroundColor White
    Write-Host "  - To start manually: run $BatchPath" -ForegroundColor White
    Write-Host ""
    Write-Host "==============================================================" -ForegroundColor Yellow
} else {
    Write-Warn "Python not found - Bridge setup skipped"
}

# --- Step 7: Smoke test --------------------------------------------------------
Write-Step 7 "Running smoke test..."

if ($SkipTests) {
    Write-Warn 'Skipping tests (--skip-tests)'
} else {
    $testScript = Join-Path $SaviaHome "scripts\test-workspace.sh"
    if (Test-Path $testScript) {
        if ($gitBash -and (Test-Path $gitBash)) {
            try {
                & $gitBash $testScript --mock 2>&1 | Out-Null
                Write-Ok "Smoke tests passed"
            } catch {
                Write-Warn 'Some tests failed (normal without Azure DevOps configured)'
            }
        } else {
            Write-Warn 'Git Bash not found - skipping tests (install Git for Windows)'
        }
    } else {
        Write-Warn "Test script not found - skipping"
    }
}

# --- Step 8: Optional — CodeGraph MCP -------------------------------------------
Write-Step 8 "Optional: CodeGraph MCP (AST indexing engine)"

Write-Info "CodeGraph indexes source code with tree-sitter and serves it via MCP."
Write-Info "Powers the .acm engine and ast-comprehension queries (35% cheaper, 70% fewer tool calls in upstream benchmarks)."
Write-Info "It is OPT-IN per project. NOT installed by default."
Write-Host ""
Write-Host "  To enable later for a specific project:"
Write-Host "    1. npm i -g @colbymchenry/codegraph"
Write-Host "    2. cd <project>; codegraph init -i"
Write-Host "    3. Set mcp.codegraph.enabled = true in opencode.json"
Write-Host "    4. Ensure .codegraph/ is in the project .gitignore (mandatory for N4)"
Write-Host ""
Write-Host "  Docs: .opencode/skills/codegraph/SKILL.md"
Write-Host "  Rule: docs/rules/domain/codegraph-confidentiality.md"

if (Get-Command codegraph -ErrorAction SilentlyContinue) {
    Write-Ok "codegraph CLI already on PATH"
} else {
    Write-Info "codegraph CLI not on PATH — install only when you need it"
}

# --- Done -----------------------------------------------------------------------
Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host "  Savia is ready!" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:"
Write-Host ""
Write-Host "    cd $SaviaHome" -ForegroundColor White
Write-Host "    opencode" -ForegroundColor White
Write-Host ""
Write-Host "  First time? Run the interactive setup:"
Write-Host "    opencode"
Write-Host "  Then say: `"Hola Savia`" or run any command like /savia-goal status"
Write-Host ""
Write-Host "  Mobile app setup:"
Write-Host "    1. Install Savia mobile app from App Store/Play Store"
Write-Host "    2. Configure Bridge endpoint: https://localhost:8922"
Write-Host "    3. Enter the auth token from $env:USERPROFILE\.savia\bridge\config.json"
Write-Host ""
Write-Host "  Docs: https://github.com/gonzalezpazmonica/pm-workspace#readme"
Write-Host "  Guide: $SaviaHome\docs\ADOPTION_GUIDE.md" -ForegroundColor White
Write-Host ""
