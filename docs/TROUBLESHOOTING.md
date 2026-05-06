# Troubleshooting

These notes are for agents installing Revit MCP on Windows machines that may
not already have developer tools installed.

For a normal Windows user install, start with `scripts/install-windows.ps1`.
Use the sections below only when that one-shot script cannot complete.

## Claude Desktop: "Could not load app settings"

Likely causes:

- `claude_desktop_config.json` was written with a UTF-8 BOM.
- The JSON is valid for Claude Code but not for Claude Desktop.
- A Windows path was pasted with unescaped backslashes.

Fix:

- Validate the JSON with a parser.
- Rewrite it as UTF-8 without BOM.
- For Claude Desktop, prefer a minimal server entry:

```json
{
  "mcpServers": {
    "mcp-server-for-revit": {
      "command": "node",
      "args": ["<repo>\\server\\build\\index.js"],
      "env": {}
    }
  }
}
```

Claude Code may store extra fields in its own config. Do not assume every
Claude Desktop build accepts those fields in `claude_desktop_config.json`.

## Revit is not found

The installer checks for Autodesk Revit 2020-2026. It cannot install Revit
itself because Autodesk licensing and account setup are user-specific.

Ask the user to install Revit, open it once, complete sign-in/licensing, close
Revit, then rerun:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

## Build tools are missing

When no matching GitHub release ZIP is available, the installer builds the
add-in from source.

Expected dependencies:

- Node.js 20+ for the MCP server.
- .NET 8 SDK for Revit 2025-2026 builds.
- Visual Studio 2022 Build Tools with MSBuild and .NET Framework 4.8 targeting
  packs for Revit 2020-2024 builds.

The installer tries to install these with `winget`. If `winget` is unavailable,
install the missing dependency manually and rerun the same script.

## Add-in files cannot be copied

Revit keeps add-in DLLs loaded while it is running. Fully close Revit, then
rerun the installer. Avoid force-killing Revit unless the user explicitly
approves it.

The expected install folder is:

```text
%APPDATA%\Autodesk\Revit\Addins\<year>\
```

It should contain:

```text
mcp-servers-for-revit.addin
revit_mcp_plugin\
```

## Revit asks whether to load the add-in

On first launch after install, Revit may show an add-in security prompt. The
user should choose **Always Load** for `mcp-servers-for-revit`.

After Revit opens, use the mcp-servers-for-revit ribbon Settings button, enable
the command set, and click Save.

## MCP starts, but connection status is false

Run the read-only tool `get_revit_connection_status`.

Common causes:

- Revit is not open.
- The add-in was not allowed at the Revit security prompt.
- The command set was not enabled in the Revit settings window.
- Another local service is already using port `8080`.
- The MCP client has not been restarted after config changes.

By default the bridge uses:

```text
REVIT_MCP_HOST=127.0.0.1
REVIT_MCP_PORT=8080
```

If the port was changed in the Revit add-in settings, set the same environment
variable on the MCP server config.

## Claude Code CLI is not found

The installer still updates Claude Desktop and Codex when those configs are
present. Once Claude Code is available, add the MCP manually from the repo root:

```powershell
claude mcp add --scope user mcp-server-for-revit -- node .\server\build\index.js
```

If `node` is not resolved by Claude Code on Windows, use the full `node.exe`
path discovered by the installer.
