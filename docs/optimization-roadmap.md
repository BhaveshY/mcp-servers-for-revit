# Revit MCP Optimization Roadmap

Target environment: Windows 11, Autodesk Revit 2024, Claude Code over local stdio MCP.

## Completed In Current Hardening Pass

- Replaced dynamic tool discovery with an explicit registry so startup is deterministic and empty placeholder files do not produce noisy warnings.
- Added server instructions for Claude Code tool search, with guidance to start from connection status and keep query limits focused.
- Added `get_revit_connection_status` as a read-only diagnostic tool that reports bridge host, port, latency, and connection errors.
- Reworked the Node TCP bridge client to reuse a shared local connection, reconnect on failure, parse concatenated JSON-RPC responses, and expose configurable host/port/timeouts through environment variables.
- Bound the Revit add-in socket listener to loopback instead of all network interfaces.
- Restored configurable plugin port support from `commandRegistry.json` settings.
- Optimized command loading by grouping enabled commands by assembly and loading/scanning each DLL once.
- Fixed current-view element queries so empty client category lists use the intended default category set instead of collecting everything in the view.
- Fixed `ai_element_filter` bounding-box schema to match the C# `JZPoint` shape (`x`, `y`, `z`).
- Added `Highlight` support to `operate_element` to match the MCP tool schema.
- Updated Claude Code setup docs to current stdio syntax and included the Windows `cmd /c npx` fallback.
- Added CI for the primary Windows/Revit 2024 target that builds the MCP server, builds `Release R24`, and verifies the add-in artifact layout.

## Next Highest-Value Improvements

1. Convert high-traffic tools from deprecated `server.tool(...)` calls to `server.registerTool(...)` with titles, output schemas, and read/write/destructive annotations.
2. Add shared response helpers that provide `structuredContent` and cap text output for large model queries.
3. Add pagination/cursor options to large read tools such as current-view elements, room export, material quantities, and model statistics.
4. Split broad tools into safer read/write variants where Claude Code permission prompts and tool search can reason more clearly.
5. Add a bridge handshake command that reports Revit version, document title/path, enabled command count, and command set version.
6. Add optional audit logging for write/destructive operations, including command name, element IDs, document path, request ID, and result.
7. Expand tests around schema parity between TypeScript tools and C# command models.
8. Add a packaging smoke test that verifies the release ZIP contains the addin, plugin DLLs, command set DLLs, and `command.json` in the exact Revit addins layout.

## Guardrails

- Keep the default bridge local-only.
- Keep Revit API mutations on the Revit external-event path.
- Prefer bounded reads by default; require explicit limits for broad model extraction.
- Treat dynamic C# execution as an advanced tool and document the transaction mode clearly.
