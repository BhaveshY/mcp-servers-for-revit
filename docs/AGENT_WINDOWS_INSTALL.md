# Agent Windows Install

This is the handoff for a Claude Code or Codex agent installing the Revit MCP
connector on a non-coding Windows user's PC.

The user should be able to paste the GitHub link and ask the agent to install
it. Do not ask the user to edit JSON, TOML, Revit add-in folders, or PowerShell
profile files by hand.

## Suggested User Prompt

```text
Install this Revit MCP repo on Windows for Claude Code, Claude Desktop, and
Codex. Follow docs/AGENT_WINDOWS_INSTALL.md, run the Windows installer, avoid
hardcoded paths from other machines, and finish with short next steps for me.
```

## One-shot Flow

1. Clone or open the repository.
2. Run the Windows installer from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

The script handles:

- Node.js 20+ detection and winget install when missing.
- Local MCP server install and TypeScript build from `server/`.
- Revit 2020-2026 detection.
- Revit add-in install for each detected Revit version.
- Release ZIP download when a matching GitHub release asset exists.
- Source build fallback when release assets are missing.
- .NET 8 SDK install when a source build is required.
- Visual Studio Build Tools install when Revit 2020-2024 source builds need MSBuild and .NET Framework 4.8 targeting packs.
- Claude Code MCP registration when a Claude Code CLI is discoverable.
- Claude Desktop JSON config updates, written as UTF-8 without BOM.
- Codex config update when `~/.codex/config.toml` exists.
- Revit launch at the end unless `-NoLaunchRevit` is passed.

No Python dependency is required.

## Revit Requirements

The installer cannot install Autodesk Revit because Revit licensing and account
setup are user-specific. If no supported Revit version is found, ask the user to
install and open Autodesk Revit 2020-2026 once, then rerun the same installer.

If Revit is running, the installer pauses and asks the user to close it before
copying add-in DLLs. Do not force-kill Revit unless the user explicitly approves.

## Common Agent Commands

Install for all detected Revit versions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

Install for one Revit version:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -RevitYears 2024
```

Install without launching Revit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1 -NoLaunchRevit
```

## Final User Message

After a successful install, keep the final explanation short:

```text
Installed Revit MCP.

Next steps:
1. Open Revit.
2. If Revit asks about the mcp-servers-for-revit add-in, choose Always Load.
3. In Revit, open the mcp-servers-for-revit Settings button, enable the command set, and click Save.
4. Restart Claude, then ask: "Use Revit MCP to check connection status."

The MCP can read and change the active Revit model only when you ask it to.
```

Do not include local paths from the install machine in the final user summary
unless the user asks where the files were installed.
