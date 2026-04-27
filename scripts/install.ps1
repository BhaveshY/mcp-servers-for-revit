<#
.SYNOPSIS
    One-shot installer for mcp-servers-for-revit on Windows.

.DESCRIPTION
    Idempotent. Every step checks "is this already done?" first, so re-running
    the script is a safe no-op for anything already in place.

    Steps:
      1. Set per-process execution policy to Bypass (Issue 5).
      2. Detect / install Node.js LTS, Python 3.12, .NET 8 SDK via winget (Issues 3, 4).
      3. Refresh PATH from machine + user scope so this process sees newly installed tools (Issue 3).
      4. Build the Revit plugin via dotnet against NuGet-resolved Revit API refs (Issue 6).
      5. Deploy plugin output into %AppData%\Autodesk\Revit\Addins\<RevitVersion>\.
      6. Install + build the MCP server (uses npm.cmd explicitly, never npm.ps1; Issue 5).
      7. Register the server in %UserProfile%\.claude.json (preserves any existing config).
      8. Smoke-test the MCP stdio handshake.

    Run from PowerShell as the target user. No elevation required for user-scope
    items; winget will prompt for elevation only if it actually needs it.

.PARAMETER RevitVersion
    Revit major version to build/deploy for. Defaults to 2024.

.PARAMETER RepoRoot
    Path to a local clone of mcp-servers-for-revit. Defaults to the parent
    directory of this script when run from inside the repo, otherwise
    %UserProfile%\Downloads\mcp-servers-for-revit (cloned if missing).

.PARAMETER Branch
    Git branch to check out when cloning. Defaults to "main".

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
#>

[CmdletBinding()]
param(
    [ValidateSet("2020","2021","2022","2023","2024","2025","2026")]
    [string]$RevitVersion = "2024",
    [string]$RepoRoot,
    [string]$Branch = "main"
)

# ────────────────────────────────────────────────────────────────────────────
# Issue 5: Set process-scope execution policy so npm.ps1, this script, and any
# Set-Content -Encoding etc. are unblocked. Process scope = no registry write,
# no admin needed, dies with this PS instance.
# ────────────────────────────────────────────────────────────────────────────
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Stop"

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────
function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    [skip] $msg" -ForegroundColor DarkGray }

# Issue 3: After winget installs something into the Machine PATH, this PowerShell
# process still has the old PATH. Recompose it from both scopes so subsequent
# Get-Command lookups see the fresh tools without needing a restart.
function Refresh-Path {
    $machine = [System.Environment]::GetEnvironmentVariable("Path","Machine")
    $user    = [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = ($machine, $user | Where-Object { $_ }) -join ";"
}

function Test-Tool {
    param([string]$Name, [string]$VersionArg = "--version")
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    try { return (& $cmd.Source $VersionArg 2>&1 | Select-Object -First 1) }
    catch { return $cmd.Source }
}

function Winget-Install-IfMissing {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$AlreadyInstalledCheck
    )
    if (& $AlreadyInstalledCheck) {
        Write-Skip "$Description already installed."
        return
    }
    Write-Step "Installing $Description ($Id) via winget..."
    & winget install -e --id $Id --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
        # -1978335189 = APPINSTALLER_CLI_ERROR_UPDATE_NOT_APPLICABLE (already current)
        throw "winget install $Id failed with exit code $LASTEXITCODE."
    }
    Refresh-Path
    Write-Ok "$Description installed."
}

# ────────────────────────────────────────────────────────────────────────────
# Resolve paths
# ────────────────────────────────────────────────────────────────────────────
$UserProfile = [Environment]::GetFolderPath("UserProfile")
$AppData     = [Environment]::GetFolderPath("ApplicationData")

if (-not $RepoRoot) {
    # If run from inside the repo, scripts/ -> repo root.
    $maybeRepo = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $maybeRepo "mcp-servers-for-revit.sln")) {
        $RepoRoot = $maybeRepo
    } else {
        $RepoRoot = Join-Path $UserProfile "Downloads\mcp-servers-for-revit"
    }
}

$AddinsDir = Join-Path $AppData "Autodesk\Revit\Addins\$RevitVersion"
$ClaudeJson = Join-Path $UserProfile ".claude.json"

# Node + npm full paths. Issues 3, 5: bash sessions and PowerShell with restrictive
# execution policy both fail to find these via PATH/aliases. Always use full paths.
$NodeExe = "C:\Program Files\nodejs\node.exe"
$NpmCmd  = "C:\Program Files\nodejs\npm.cmd"

Write-Step "Repo root:    $RepoRoot"
Write-Step "Revit ver:    $RevitVersion"
Write-Step "Addins dir:   $AddinsDir"
Write-Step "Branch:       $Branch"

# ────────────────────────────────────────────────────────────────────────────
# Step 2: prerequisites
# ────────────────────────────────────────────────────────────────────────────
Refresh-Path

# Issue 3: Node.js
Winget-Install-IfMissing -Id "OpenJS.NodeJS.LTS" -Description "Node.js LTS" -AlreadyInstalledCheck {
    Test-Path $NodeExe
}
if (-not (Test-Path $NodeExe)) { throw "Node.js not found at $NodeExe even after install attempt." }
Write-Ok "Node:   $(& $NodeExe --version)"

# Issue 4: Python (required for better-sqlite3 native build via node-gyp)
Winget-Install-IfMissing -Id "Python.Python.3.12" -Description "Python 3.12" -AlreadyInstalledCheck {
    [bool](Get-Command python -ErrorAction SilentlyContinue) -or
    [bool](Get-Command python3 -ErrorAction SilentlyContinue)
}
$pythonCmd = (Get-Command python -ErrorAction SilentlyContinue) ?? (Get-Command python3 -ErrorAction SilentlyContinue)
if (-not $pythonCmd) { throw "Python not on PATH after install." }
Write-Ok "Python: $(& $pythonCmd.Source --version)"

# .NET 8 SDK
Winget-Install-IfMissing -Id "Microsoft.DotNet.SDK.8" -Description ".NET 8 SDK" -AlreadyInstalledCheck {
    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) { return $false }
    return ((& $dotnet.Source --list-sdks) -match "^8\.")
}
Refresh-Path
$dotnetExe = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
if (-not $dotnetExe) { throw "dotnet not on PATH after install." }
Write-Ok ".NET SDKs: $(& $dotnetExe --list-sdks | Out-String -Stream | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 3 | Join-String -Separator '; ')"

# Git
$gitExe = (Get-Command git -ErrorAction SilentlyContinue)?.Source
if (-not $gitExe) {
    Winget-Install-IfMissing -Id "Git.Git" -Description "Git" -AlreadyInstalledCheck { $false }
    $gitExe = (Get-Command git -ErrorAction SilentlyContinue)?.Source
    if (-not $gitExe) { throw "git not on PATH after install." }
}

# ────────────────────────────────────────────────────────────────────────────
# Step 2.5: clone or update repo (idempotent)
# ────────────────────────────────────────────────────────────────────────────
if (Test-Path (Join-Path $RepoRoot ".git")) {
    Write-Step "Repo present. Fetching..."
    & $gitExe -C $RepoRoot fetch --quiet origin
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed." }
    & $gitExe -C $RepoRoot checkout $Branch
    & $gitExe -C $RepoRoot pull --ff-only origin $Branch
    Write-Ok "Repo at $(& $gitExe -C $RepoRoot log -1 --oneline)"
} elseif (Test-Path $RepoRoot) {
    throw "Path $RepoRoot exists but is not a git repo. Refusing to overwrite."
} else {
    Write-Step "Cloning into $RepoRoot ..."
    & $gitExe clone --branch $Branch https://github.com/BhaveshY/mcp-servers-for-revit.git $RepoRoot
    if ($LASTEXITCODE -ne 0) { throw "git clone failed." }
    Write-Ok "Cloned."
}

# ────────────────────────────────────────────────────────────────────────────
# Step 3: build Revit plugin
# Issue 6: NuGet-based references (Nice3point.Revit.Api.*) handle the Revit API,
# so no on-disk RevitAPI.dll probing is needed. Just hand the solution to dotnet.
# ────────────────────────────────────────────────────────────────────────────
Write-Step "Building Revit plugin (Release R$RevitVersion)..."
& $dotnetExe build (Join-Path $RepoRoot "mcp-servers-for-revit.sln") `
    -c "Release R$RevitVersion" -v minimal --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (Release R$RevitVersion)." }
Write-Ok "Plugin build succeeded."

# ────────────────────────────────────────────────────────────────────────────
# Step 4: deploy plugin into Revit Addins
# ────────────────────────────────────────────────────────────────────────────
$BuildOut = Join-Path $RepoRoot "plugin\bin\AddIn $RevitVersion Release R$RevitVersion"
if (-not (Test-Path $BuildOut)) {
    throw "Expected build output not found at $BuildOut. Build target may have changed."
}
if (-not (Test-Path $AddinsDir)) {
    New-Item -ItemType Directory -Path $AddinsDir -Force | Out-Null
}
Write-Step "Deploying plugin -> $AddinsDir"
Copy-Item -Path (Join-Path $BuildOut "*") -Destination $AddinsDir -Recurse -Force
Write-Ok "Deployed."

# ────────────────────────────────────────────────────────────────────────────
# Step 5: build the MCP server
# Issue 5: use npm.cmd, NOT npm.ps1. PowerShell execution policy blocks the .ps1 shim.
# Issue 4: requires Python on PATH for better-sqlite3 native build (handled above).
# ────────────────────────────────────────────────────────────────────────────
$ServerDir = Join-Path $RepoRoot "server"
$EntryPoint = Join-Path $ServerDir "build\index.js"
$pkgJsonPath = Join-Path $ServerDir "package.json"
$pkgLockPath = Join-Path $ServerDir "package-lock.json"

# Detect whether deps are already installed and current. Reinstall only if package
# files are newer than node_modules' install marker.
$needsInstall = $true
$nodeModules = Join-Path $ServerDir "node_modules"
if (Test-Path $nodeModules) {
    $installMarker = Join-Path $nodeModules ".package-lock.json"
    if (Test-Path $installMarker) {
        $markerTime = (Get-Item $installMarker).LastWriteTimeUtc
        $pkgTime = (Get-Item $pkgJsonPath).LastWriteTimeUtc
        $lockTime = if (Test-Path $pkgLockPath) { (Get-Item $pkgLockPath).LastWriteTimeUtc } else { [datetime]::MinValue }
        if ($markerTime -ge $pkgTime -and $markerTime -ge $lockTime) {
            $needsInstall = $false
        }
    }
}
if ($needsInstall) {
    Write-Step "Running npm.cmd install in $ServerDir ..."
    Push-Location $ServerDir
    try {
        & $NpmCmd install
        if ($LASTEXITCODE -ne 0) { throw "npm install failed (exit $LASTEXITCODE)." }
    } finally { Pop-Location }
    Write-Ok "npm install complete."
} else {
    Write-Skip "node_modules is up to date."
}

# Always run the build to ensure build/ is in sync with src/.
Write-Step "Building MCP server (tsc)..."
Push-Location $ServerDir
try {
    & $NpmCmd run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed (exit $LASTEXITCODE)." }
} finally { Pop-Location }
if (-not (Test-Path $EntryPoint)) {
    throw "Server build did not produce $EntryPoint."
}
Write-Ok "Server entry: $EntryPoint"

# ────────────────────────────────────────────────────────────────────────────
# Step 6: register the connector in .claude.json (idempotent)
# ────────────────────────────────────────────────────────────────────────────
Write-Step "Registering MCP connector in $ClaudeJson ..."
$config = if (Test-Path $ClaudeJson) {
    try { Get-Content $ClaudeJson -Raw | ConvertFrom-Json }
    catch { throw "Existing .claude.json is not valid JSON: $_" }
} else {
    [PSCustomObject]@{}
}
if (-not $config.PSObject.Properties["mcpServers"]) {
    $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
}
$desiredEntry = [PSCustomObject]@{
    type    = "stdio"
    command = $NodeExe
    args    = @($EntryPoint)
    env     = [PSCustomObject]@{}
}
$existing = $config.mcpServers.PSObject.Properties["mcp-server-for-revit"]
$same = $false
if ($existing) {
    $existingJson = ($existing.Value | ConvertTo-Json -Depth 10 -Compress)
    $desiredJson  = ($desiredEntry  | ConvertTo-Json -Depth 10 -Compress)
    $same = ($existingJson -eq $desiredJson)
}
if ($same) {
    Write-Skip "Connector already registered with the desired settings."
} else {
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "mcp-server-for-revit" `
        -Value $desiredEntry -Force
    $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeJson -Encoding utf8
    Write-Ok "Connector registered."
}

# ────────────────────────────────────────────────────────────────────────────
# Step 7: stdio handshake smoke test
# ────────────────────────────────────────────────────────────────────────────
Write-Step "Smoke-testing MCP stdio handshake..."
$req = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"install-probe","version":"1.0"}}}'
$psi = [System.Diagnostics.ProcessStartInfo]@{
    FileName               = $NodeExe
    Arguments              = "`"$EntryPoint`""
    RedirectStandardInput  = $true
    RedirectStandardOutput = $true
    RedirectStandardError  = $true
    UseShellExecute        = $false
    CreateNoWindow         = $true
}
$p = [System.Diagnostics.Process]::Start($psi)
try {
    $p.StandardInput.WriteLine($req)
    $p.StandardInput.Flush()
    $p.StandardInput.Close()
    $deadline = [DateTime]::Now.AddSeconds(10)
    $stdout = New-Object System.Text.StringBuilder
    while ([DateTime]::Now -lt $deadline) {
        if ($p.StandardOutput.Peek() -ne -1) {
            $line = $p.StandardOutput.ReadLine()
            [void]$stdout.AppendLine($line)
            if ($line -match '"result"') { break }
        } else {
            Start-Sleep -Milliseconds 100
        }
        if ($p.HasExited) { break }
    }
    $output = $stdout.ToString()
    if ($output -match '"result"') {
        Write-Ok "Smoke test passed (server responded with a result)."
    } else {
        Write-Warning "Smoke test inconclusive. stdout was: $output"
        $stderr = $p.StandardError.ReadToEnd()
        if ($stderr) { Write-Warning "stderr: $stderr" }
    }
} finally {
    if (-not $p.HasExited) { try { $p.Kill() } catch {} }
    $p.Dispose()
}

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Restart Claude Desktop / Claude Code so it re-reads .claude.json."
Write-Host "  2. Open Revit $RevitVersion."
Write-Host "  3. Ribbon -> Add-Ins -> Revit MCP Plugin -> Revit MCP Switch (Open Server)."
Write-Host "  4. Open a floor plan, section, or 3D view before invoking Revit tools (schedules don't support all commands)."
