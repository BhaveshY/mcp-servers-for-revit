param(
  [int[]]$RevitYears = @(),
  [switch]$SkipDependencyInstall,
  [switch]$SkipAddinInstall,
  [switch]$SkipServerBuild,
  [switch]$SkipClaudeCodeConfig,
  [switch]$SkipClaudeDesktopConfig,
  [switch]$SkipCodexConfig,
  [switch]$PreferSourceBuild,
  [switch]$NoLaunchRevit,
  [string]$GitHubRepository = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$supportedRevitYears = @(2020, 2021, 2022, 2023, 2024, 2025, 2026)
$script:ResolvedGitHubRepository = $null

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Write-Result {
  param([string]$Message)
  Write-Host "OK  $Message"
}

function Refresh-Path {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = (($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Join-OptionalPath {
  param(
    [string]$Base,
    [string]$Child
  )
  if (-not $Base) {
    return $null
  }
  return Join-Path $Base $Child
}

function Find-Executable {
  param(
    [string[]]$Names,
    [string[]]$ExtraPaths = @()
  )

  foreach ($name in $Names) {
    $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and $command.Source) {
      return $command.Source
    }
  }

  foreach ($path in $ExtraPaths) {
    if ($path -and (Test-Path -LiteralPath $path)) {
      return (Resolve-Path -LiteralPath $path).Path
    }
  }

  return $null
}

function Invoke-Checked {
  param(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$FailureMessage
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FailureMessage Exit code: $LASTEXITCODE"
  }
}

function Resolve-GitHubRepository {
  param([string]$RepoRoot)

  if ($GitHubRepository) {
    return $GitHubRepository
  }

  $git = Find-Executable -Names @("git.exe", "git")
  if (-not $git) {
    return $null
  }

  Push-Location $RepoRoot
  try {
    $remote = (& $git config --get remote.origin.url) -join ""
  } finally {
    Pop-Location
  }

  if (-not $remote) {
    return $null
  }

  $remote = $remote.Trim()
  if ($remote -match "github\.com[:/](?<owner>[^/]+)/(?<repo>[^/.]+)(?:\.git)?$") {
    return "$($Matches.owner)/$($Matches.repo)"
  }

  return $null
}

function Install-WingetPackage {
  param(
    [string]$PackageId,
    [string]$DisplayName,
    [string]$Override = ""
  )

  if ($SkipDependencyInstall) {
    throw "$DisplayName is missing. Dependency install is disabled for this run."
  }

  $winget = Find-Executable -Names @("winget.exe", "winget")
  if (-not $winget) {
    throw "$DisplayName is missing and winget is not available. Install $DisplayName, then rerun this script."
  }

  Write-Step "Installing $DisplayName with winget"
  $baseArgs = @("install", "--id", $PackageId, "--exact", "--accept-package-agreements", "--accept-source-agreements")
  if ($Override) {
    $baseArgs += @("--override", $Override)
  }

  & $winget @($baseArgs + @("--silent"))
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Silent winget install failed. Retrying without --silent so Windows can show prompts."
    & $winget @baseArgs
  }
  if ($LASTEXITCODE -ne 0) {
    throw "winget could not install $DisplayName. Exit code: $LASTEXITCODE"
  }
  Refresh-Path
}

function Find-Node {
  $extra = @(
    (Join-OptionalPath $env:ProgramFiles "nodejs\node.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "nodejs\node.exe"),
    (Join-OptionalPath $env:LOCALAPPDATA "Programs\nodejs\node.exe")
  )
  return Find-Executable -Names @("node.exe", "node") -ExtraPaths $extra
}

function Find-Npm {
  $extra = @(
    (Join-OptionalPath $env:ProgramFiles "nodejs\npm.cmd"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "nodejs\npm.cmd"),
    (Join-OptionalPath $env:LOCALAPPDATA "Programs\nodejs\npm.cmd")
  )
  return Find-Executable -Names @("npm.cmd", "npm") -ExtraPaths $extra
}

function Get-NodeMajor {
  param([string]$NodePath)
  try {
    $version = & $NodePath -p "process.versions.node"
    return [int]($version.Split(".")[0])
  } catch {
    return 0
  }
}

function Ensure-Node {
  $node = Find-Node
  if (-not $node -or (Get-NodeMajor $node) -lt 20) {
    Install-WingetPackage -PackageId "OpenJS.NodeJS.LTS" -DisplayName "Node.js 20 or newer"
    $node = Find-Node
  }

  if (-not $node -or (Get-NodeMajor $node) -lt 20) {
    throw "Node.js 20 or newer is required but was not found after installation."
  }

  $npm = Find-Npm
  if (-not $npm) {
    throw "npm was not found after Node.js installation."
  }

  return [pscustomobject]@{ Node = $node; Npm = $npm }
}

function Find-DotNet {
  $extra = @(
    (Join-OptionalPath $env:ProgramFiles "dotnet\dotnet.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "dotnet\dotnet.exe")
  )
  return Find-Executable -Names @("dotnet.exe", "dotnet") -ExtraPaths $extra
}

function Has-DotNetSdkMajor {
  param(
    [string]$DotNetPath,
    [int]$Major
  )
  try {
    $sdks = & $DotNetPath --list-sdks
    foreach ($sdk in $sdks) {
      if ($sdk -match "^(\d+)\.") {
        if ([int]$Matches[1] -ge $Major) {
          return $true
        }
      }
    }
  } catch {
    return $false
  }
  return $false
}

function Ensure-DotNetSdk {
  $dotnet = Find-DotNet
  if (-not $dotnet -or -not (Has-DotNetSdkMajor -DotNetPath $dotnet -Major 8)) {
    Install-WingetPackage -PackageId "Microsoft.DotNet.SDK.8" -DisplayName ".NET 8 SDK"
    $dotnet = Find-DotNet
  }

  if (-not $dotnet -or -not (Has-DotNetSdkMajor -DotNetPath $dotnet -Major 8)) {
    throw ".NET 8 SDK or newer is required but was not found after installation."
  }

  return $dotnet
}

function Find-MSBuild {
  $extra = @(
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\MSBuild.exe")
  )

  $msbuild = Find-Executable -Names @("MSBuild.exe", "msbuild") -ExtraPaths $extra
  if ($msbuild) {
    return $msbuild
  }

  $vswherePaths = @(
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
    (Join-OptionalPath $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
  )

  foreach ($vswhere in $vswherePaths) {
    if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
      $found = & $vswhere -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe"
      foreach ($path in $found) {
        if ($path -and (Test-Path -LiteralPath $path)) {
          return (Resolve-Path -LiteralPath $path).Path
        }
      }
    }
  }

  return $null
}

function Ensure-MSBuild {
  $msbuild = Find-MSBuild
  if (-not $msbuild) {
    $override = "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.MSBuildTools --add Microsoft.VisualStudio.Workload.ManagedDesktopBuildTools --add Microsoft.Net.Component.4.8.SDK --add Microsoft.Net.Component.4.8.TargetingPack --includeRecommended"
    Install-WingetPackage -PackageId "Microsoft.VisualStudio.2022.BuildTools" -DisplayName "Visual Studio 2022 Build Tools" -Override $override
    $msbuild = Find-MSBuild
  }

  if (-not $msbuild) {
    throw "MSBuild was not found after installing Visual Studio Build Tools."
  }

  return $msbuild
}

function Get-RevitExecutable {
  param([int]$Year)
  $paths = @(
    (Join-OptionalPath $env:ProgramFiles "Autodesk\Revit $Year\Revit.exe"),
    (Join-OptionalPath ${env:ProgramFiles(x86)} "Autodesk\Revit $Year\Revit.exe")
  )
  foreach ($path in $paths) {
    if ($path -and (Test-Path -LiteralPath $path)) {
      return (Resolve-Path -LiteralPath $path).Path
    }
  }
  return $null
}

function Get-InstalledRevitYears {
  $years = New-Object System.Collections.Generic.List[int]

  foreach ($year in $supportedRevitYears) {
    if (Get-RevitExecutable -Year $year) {
      [void]$years.Add($year)
    }
  }

  $uninstallRoots = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
  )

  foreach ($root in $uninstallRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
      continue
    }
    Get-ChildItem -Path $root -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $displayName = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop).DisplayName
        if ($displayName -and $displayName -match "Autodesk Revit\s+(\d{4})") {
          $year = [int]$Matches[1]
          if ($supportedRevitYears -contains $year) {
            [void]$years.Add($year)
          }
        }
      } catch {
      }
    }
  }

  return @($years | Sort-Object -Unique)
}

function Resolve-RevitYears {
  if ($RevitYears.Count -gt 0) {
    foreach ($year in $RevitYears) {
      if ($supportedRevitYears -notcontains $year) {
        throw "Unsupported Revit year: $year. Supported years: $($supportedRevitYears -join ', ')."
      }
    }
    return @($RevitYears | Sort-Object -Unique)
  }

  $installed = @(Get-InstalledRevitYears)
  if ($installed.Count -eq 0) {
    throw "No supported Revit installation was found. Install Autodesk Revit 2020-2026, open it once for licensing, then rerun this script."
  }

  return $installed
}

function Wait-ForRevitClosed {
  $processes = @(Get-Process -Name Revit -ErrorAction SilentlyContinue)
  if ($processes.Count -eq 0) {
    return
  }

  Write-Warning "Revit is currently running. Save work and close Revit before the add-in files are copied."
  [void](Read-Host "Press Enter after Revit is closed")

  $processes = @(Get-Process -Name Revit -ErrorAction SilentlyContinue)
  if ($processes.Count -gt 0) {
    throw "Revit is still running. Close Revit completely and rerun this script."
  }
}

function Get-RevitConfigName {
  param([int]$Year)
  $suffix = "{0:D2}" -f ($Year % 100)
  return "Release R$suffix"
}

function Remove-SafeTree {
  param(
    [string]$Path,
    [string]$AllowedRoot
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $fullRoot = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $fullPath = [IO.Path]::GetFullPath($Path)
  if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove path outside target addins directory: $fullPath"
  }

  Remove-Item -LiteralPath $fullPath -Recurse -Force
}

function Assert-AddinLayout {
  param([string]$SourceRoot)

  $required = @(
    (Join-Path $SourceRoot "mcp-servers-for-revit.addin"),
    (Join-Path $SourceRoot "revit_mcp_plugin\RevitMCPPlugin.dll"),
    (Join-Path $SourceRoot "revit_mcp_plugin\Commands\RevitMCPCommandSet\command.json")
  )

  foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Add-in layout is incomplete. Missing: $path"
    }
  }
}

function Install-AddinLayout {
  param(
    [int]$Year,
    [string]$SourceRoot
  )

  Assert-AddinLayout -SourceRoot $SourceRoot

  $targetRoot = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$Year"
  New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

  $targetAddin = Join-Path $targetRoot "mcp-servers-for-revit.addin"
  $targetPlugin = Join-Path $targetRoot "revit_mcp_plugin"

  Remove-SafeTree -Path $targetPlugin -AllowedRoot $targetRoot
  Copy-Item -LiteralPath (Join-Path $SourceRoot "mcp-servers-for-revit.addin") -Destination $targetAddin -Force
  Copy-Item -LiteralPath (Join-Path $SourceRoot "revit_mcp_plugin") -Destination $targetPlugin -Recurse -Force

  $yearCommandSet = Join-Path $targetPlugin "Commands\RevitMCPCommandSet\$Year\RevitMCPCommandSet.dll"
  if (-not (Test-Path -LiteralPath $yearCommandSet)) {
    throw "Installed add-in is missing the Revit $Year command set: $yearCommandSet"
  }

  return $targetRoot
}

function Find-GitHubReleaseAssetUrl {
  param([int]$Year)

  if ($PreferSourceBuild) {
    return $null
  }

  if (-not $script:ResolvedGitHubRepository) {
    return $null
  }

  try {
    $headers = @{ "User-Agent" = "revit-mcp-windows-installer" }
    $uri = "https://api.github.com/repos/$script:ResolvedGitHubRepository/releases?per_page=20"
    $releases = @(Invoke-RestMethod -Uri $uri -Headers $headers)
    foreach ($release in $releases) {
      $propertyNames = @($release.PSObject.Properties.Name)
      if (($propertyNames -contains "draft") -and $release.draft) {
        continue
      }
      if ($propertyNames -notcontains "assets") {
        continue
      }
      foreach ($asset in @($release.assets)) {
        if ($asset.name -match "Revit$Year\.zip$") {
          return $asset.browser_download_url
        }
      }
    }
  } catch {
    Write-Warning "Could not query GitHub releases. Falling back to source build. $($_.Exception.Message)"
  }

  return $null
}

function Resolve-ExtractedAddinRoot {
  param([string]$ExtractRoot)

  $candidates = New-Object System.Collections.Generic.List[string]
  [void]$candidates.Add($ExtractRoot)
  Get-ChildItem -LiteralPath $ExtractRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    [void]$candidates.Add($_.FullName)
  }

  foreach ($candidate in $candidates) {
    $addin = Join-Path $candidate "mcp-servers-for-revit.addin"
    $pluginDll = Join-Path $candidate "revit_mcp_plugin\RevitMCPPlugin.dll"
    if ((Test-Path -LiteralPath $addin) -and (Test-Path -LiteralPath $pluginDll)) {
      return $candidate
    }
  }

  throw "Downloaded release ZIP did not contain the expected add-in layout."
}

function Install-AddinFromRelease {
  param([int]$Year)

  $assetUrl = Find-GitHubReleaseAssetUrl -Year $Year
  if (-not $assetUrl) {
    return $false
  }

  Write-Step "Downloading Revit $Year add-in release asset"
  $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("revit-mcp-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  try {
    $zipPath = Join-Path $tempRoot "addin.zip"
    $extractRoot = Join-Path $tempRoot "extract"
    Invoke-WebRequest -Uri $assetUrl -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot -Force
    $sourceRoot = Resolve-ExtractedAddinRoot -ExtractRoot $extractRoot
    $target = Install-AddinLayout -Year $Year -SourceRoot $sourceRoot
    Write-Result "Installed Revit $Year add-in from release asset to $target"
    return $true
  } finally {
    Remove-SafeTree -Path $tempRoot -AllowedRoot ([IO.Path]::GetTempPath())
  }
}

function Build-AddinFromSource {
  param(
    [int]$Year,
    [string]$DotNetPath,
    [string]$MSBuildPath
  )

  $config = Get-RevitConfigName -Year $Year
  Write-Step "Building Revit $Year add-in from source ($config)"

  if ($Year -le 2024) {
    if (-not $MSBuildPath) {
      $MSBuildPath = Ensure-MSBuild
    }
    Invoke-Checked -FilePath $MSBuildPath -Arguments @("plugin\RevitMCPPlugin.csproj", "-restore", "-p:Configuration=$config") -FailureMessage "Revit $Year plugin build failed."
    Invoke-Checked -FilePath $MSBuildPath -Arguments @("commandset\RevitMCPCommandSet.csproj", "-restore", "-p:Configuration=$config") -FailureMessage "Revit $Year command set build failed."
  } else {
    if (-not $DotNetPath) {
      $DotNetPath = Ensure-DotNetSdk
    }
    Invoke-Checked -FilePath $DotNetPath -Arguments @("build", "plugin\RevitMCPPlugin.csproj", "-c", $config) -FailureMessage "Revit $Year plugin build failed."
    Invoke-Checked -FilePath $DotNetPath -Arguments @("build", "commandset\RevitMCPCommandSet.csproj", "-c", $config) -FailureMessage "Revit $Year command set build failed."
  }

  $output = Join-Path $repoRoot "plugin\bin\AddIn $Year $config"
  Assert-AddinLayout -SourceRoot $output
  return $output
}

function Build-McpServer {
  param(
    [string]$NpmPath,
    [string]$ServerDir
  )

  Write-Step "Installing npm packages and building MCP server"
  Push-Location $ServerDir
  try {
    $installCommand = "install"
    if (Test-Path -LiteralPath (Join-Path $ServerDir "package-lock.json")) {
      $installCommand = "ci"
    }
    Invoke-Checked -FilePath $NpmPath -Arguments @($installCommand) -FailureMessage "npm $installCommand failed."
    Invoke-Checked -FilePath $NpmPath -Arguments @("run", "build") -FailureMessage "npm run build failed."
  } finally {
    Pop-Location
  }
}

function Find-ClaudeCode {
  $paths = @()
  $command = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command -and $command.Source) {
    $paths += $command.Source
  }

  $roots = @(
    (Join-Path $env:APPDATA "Claude\claude-code"),
    (Join-Path $env:LOCALAPPDATA "Packages")
  )

  if (Test-Path -LiteralPath $roots[0]) {
    $paths += Get-ChildItem -Path $roots[0] -Recurse -Filter claude.exe -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -ExpandProperty FullName
  }

  if (Test-Path -LiteralPath $roots[1]) {
    $paths += Get-ChildItem -Path $roots[1] -Directory -Filter "Claude_*" -ErrorAction SilentlyContinue |
      ForEach-Object { Join-Path $_.FullName "LocalCache\Roaming\Claude\claude-code" } |
      Where-Object { Test-Path -LiteralPath $_ } |
      ForEach-Object { Get-ChildItem -Path $_ -Recurse -Filter claude.exe -File -ErrorAction SilentlyContinue } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -ExpandProperty FullName
  }

  $found = @($paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique | Select-Object -First 1)
  if ($found.Count -eq 0) {
    return $null
  }
  return $found[0]
}

function Configure-ClaudeCode {
  param(
    [string]$ClaudeExe,
    [string]$NodePath,
    [string]$ServerEntry
  )

  if (-not $ClaudeExe) {
    Write-Warning "Claude Code CLI was not found. The agent can add this MCP later with: claude mcp add --scope user mcp-server-for-revit -- `"$NodePath`" `"$ServerEntry`""
    return
  }

  Write-Step "Configuring Claude Code MCP"
  & $ClaudeExe mcp remove --scope user mcp-server-for-revit | Out-Host
  & $ClaudeExe mcp add --scope user mcp-server-for-revit -- $NodePath $ServerEntry
  if ($LASTEXITCODE -ne 0) {
    throw "Claude Code MCP configuration failed."
  }
  & $ClaudeExe mcp list | Out-Host
}

function Get-ClaudeDesktopConfigPaths {
  $paths = New-Object System.Collections.Generic.List[string]
  $paths.Add((Join-Path $env:APPDATA "Claude\claude_desktop_config.json"))

  $packagesRoot = Join-Path $env:LOCALAPPDATA "Packages"
  if (Test-Path -LiteralPath $packagesRoot) {
    Get-ChildItem -Path $packagesRoot -Directory -Filter "Claude_*" -ErrorAction SilentlyContinue |
      ForEach-Object {
        $paths.Add((Join-Path $_.FullName "LocalCache\Roaming\Claude\claude_desktop_config.json"))
        $paths.Add((Join-Path $_.FullName "LocalCache\Roaming\Claude-3p\claude_desktop_config.json"))
      }
  }

  return $paths | Select-Object -Unique
}

function Update-ClaudeDesktopConfig {
  param(
    [string]$ConfigPath,
    [string]$NodePath,
    [string]$ServerEntry
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ConfigPath) | Out-Null
  if (Test-Path -LiteralPath $ConfigPath) {
    $item = Get-Item -LiteralPath $ConfigPath
    if ($item.IsReadOnly) {
      $item.IsReadOnly = $false
    }
    Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.bak-revit-mcp" -Force
    $raw = [IO.File]::ReadAllText($ConfigPath).TrimStart([char]0xfeff)
  } else {
    $raw = "{}"
  }

  if ([string]::IsNullOrWhiteSpace($raw)) {
    $raw = "{}"
  }

  try {
    $config = $raw | ConvertFrom-Json
  } catch {
    if (Test-Path -LiteralPath $ConfigPath) {
      Copy-Item -LiteralPath $ConfigPath -Destination "$ConfigPath.invalid-revit-mcp" -Force
    }
    $config = "{}" | ConvertFrom-Json
  }

  if ($null -eq $config.mcpServers) {
    $config | Add-Member -MemberType NoteProperty -Name mcpServers -Value ([pscustomobject]@{})
  }

  $server = [ordered]@{
    command = $NodePath
    args = @($ServerEntry)
    env = [pscustomobject]@{}
  }

  if ($config.mcpServers.PSObject.Properties.Name -contains "mcp-server-for-revit") {
    $config.mcpServers."mcp-server-for-revit" = $server
  } else {
    $config.mcpServers | Add-Member -MemberType NoteProperty -Name "mcp-server-for-revit" -Value $server
  }

  $json = $config | ConvertTo-Json -Depth 20
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($ConfigPath, $json, $utf8NoBom)
}

function Update-CodexConfig {
  param(
    [string]$NodePath,
    [string]$ServerEntry
  )

  $configPath = Join-Path $HOME ".codex\config.toml"
  if (-not (Test-Path -LiteralPath $configPath)) {
    return
  }

  Copy-Item -LiteralPath $configPath -Destination "$configPath.bak-revit-mcp" -Force
  $nodeToml = $NodePath.Replace("'", "''")
  $entryToml = $ServerEntry.Replace("'", "''")
  $block = "[mcp_servers.mcp-server-for-revit]`r`ncommand = '$nodeToml'`r`nargs = ['$entryToml']`r`n"
  $content = [IO.File]::ReadAllText($configPath)
  $content = [regex]::Replace($content, "(?ms)^\[mcp_servers\.mcp-server-for-revit\]\s*.*?(?=^\[|\z)", "")
  $content = $content.TrimEnd() + "`r`n`r`n" + $block
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($configPath, $content, $utf8NoBom)
}

if ($env:OS -ne "Windows_NT") {
  throw "This installer is for Windows only."
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$serverDir = Join-Path $repoRoot "server"
$serverEntry = Join-Path $serverDir "build\index.js"
$script:ResolvedGitHubRepository = Resolve-GitHubRepository -RepoRoot $repoRoot

Write-Step "Preparing dependencies"
$nodeTools = Ensure-Node
if ($script:ResolvedGitHubRepository) {
  Write-Result "GitHub repository: $script:ResolvedGitHubRepository"
} else {
  Write-Warning "GitHub repository could not be resolved from origin; release ZIP lookup will be skipped."
}
$node = $nodeTools.Node
$npm = $nodeTools.Npm
Write-Result "Node: $node"
Write-Result "npm: $npm"

if (-not $SkipServerBuild) {
  Build-McpServer -NpmPath $npm -ServerDir $serverDir
}

if (-not (Test-Path -LiteralPath $serverEntry)) {
  throw "MCP server entry point was not built: $serverEntry"
}

$targetYears = @()
if (-not $SkipAddinInstall) {
  $targetYears = @(Resolve-RevitYears)
  Write-Result "Target Revit versions: $($targetYears -join ', ')"
  Wait-ForRevitClosed

  $needsSourceBuild = $false
  $sourceBuildYears = New-Object System.Collections.Generic.List[int]

  foreach ($year in $targetYears) {
    $installedFromRelease = Install-AddinFromRelease -Year $year
    if (-not $installedFromRelease) {
      $needsSourceBuild = $true
      [void]$sourceBuildYears.Add($year)
    }
  }

  $dotnet = $null
  $msbuild = $null
  if ($needsSourceBuild) {
    $dotnet = Ensure-DotNetSdk
    Write-Result ".NET: $dotnet"
    if (@($sourceBuildYears | Where-Object { $_ -le 2024 }).Count -gt 0) {
      $msbuild = Ensure-MSBuild
      Write-Result "MSBuild: $msbuild"
    }
  }

  Push-Location $repoRoot
  try {
    foreach ($year in $sourceBuildYears) {
      $sourceRoot = Build-AddinFromSource -Year $year -DotNetPath $dotnet -MSBuildPath $msbuild
      $target = Install-AddinLayout -Year $year -SourceRoot $sourceRoot
      Write-Result "Installed Revit $year add-in to $target"
    }
  } finally {
    Pop-Location
  }
}

if (-not $SkipClaudeCodeConfig) {
  Configure-ClaudeCode -ClaudeExe (Find-ClaudeCode) -NodePath $node -ServerEntry $serverEntry
}

if (-not $SkipClaudeDesktopConfig) {
  Write-Step "Configuring Claude Desktop JSON if present"
  $standardConfig = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
  foreach ($configPath in Get-ClaudeDesktopConfigPaths) {
    if ((Test-Path -LiteralPath $configPath) -or $configPath -eq $standardConfig) {
      Update-ClaudeDesktopConfig -ConfigPath $configPath -NodePath $node -ServerEntry $serverEntry
      Write-Result "Updated $configPath"
    }
  }
}

if (-not $SkipCodexConfig) {
  Write-Step "Configuring Codex if ~/.codex/config.toml exists"
  Update-CodexConfig -NodePath $node -ServerEntry $serverEntry
}

if (-not $NoLaunchRevit -and $targetYears.Count -gt 0) {
  $launchYear = @($targetYears | Sort-Object -Descending | Select-Object -First 1)[0]
  $revitExe = Get-RevitExecutable -Year $launchYear
  if ($revitExe) {
    Write-Step "Starting Revit $launchYear"
    Start-Process -FilePath $revitExe | Out-Null
  }
}

Write-Host ""
Write-Host "Revit MCP install complete."
Write-Host ""
Write-Host "Next steps for the user:"
Write-Host "1. Open Revit, or wait for it to finish opening if the installer launched it."
Write-Host "2. If Revit asks about the mcp-servers-for-revit add-in, choose Always Load."
Write-Host "3. In Revit, open the mcp-servers-for-revit Settings button, enable the command set, and click Save."
Write-Host "4. Restart Claude Desktop or Claude Code, then ask: Use Revit MCP to check connection status."
