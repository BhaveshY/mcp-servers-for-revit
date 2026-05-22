# mcp-server-for-revit

MCP server for interacting with Autodesk Revit through AI assistants like Claude.

This package is the MCP server component of [mcp-servers-for-revit](https://github.com/BhaveshY/mcp-servers-for-revit). It exposes Revit operations as MCP tools that AI clients can call. The server communicates with the [Revit plugin](https://github.com/BhaveshY/mcp-servers-for-revit) over local TCP JSON-RPC to execute commands inside Revit.

> [!NOTE]
> This server requires the mcp-servers-for-revit Revit plugin to be installed and running inside Revit. See the [full project README](https://github.com/BhaveshY/mcp-servers-for-revit) for setup instructions.

## MCP 2026-07-28 RC readiness note

The MCP server uses `StdioServerTransport` from `@modelcontextprotocol/sdk`. Per the official [MCP 2026-07-28 release-candidate notes](https://blog.modelcontextprotocol.io/posts/2026-07-28-release-candidate/), the new `Mcp-Method`/`Mcp-Name` HTTP header requirements apply to Streamable HTTP transports and do not affect this stdio-only server. The removal of `Mcp-Session-Id` and protocol-managed sessions also does not map to the local Revit TCP bridge; that socket/connection state is application implementation state for communicating with Revit, not MCP protocol session state.

This package updates the MCP TypeScript SDK dependency for RC readiness, but does not claim full protocol-version support beyond the stdio server behavior described above.

## Setup

**Claude Code**

```bash
claude mcp add --transport stdio mcp-server-for-revit -- npx -y mcp-server-for-revit
```

On Windows, if `npx` is not resolved directly by Claude Code, use:

```bash
claude mcp add --transport stdio mcp-server-for-revit -- cmd /c npx -y mcp-server-for-revit
```

**Claude Desktop**

Claude Desktop → Settings → Developer → Edit Config → `claude_desktop_config.json`:

```json
{
    "mcpServers": {
        "mcp-server-for-revit": {
            "command": "npx",
            "args": ["-y", "mcp-server-for-revit"]
        }
    }
}
```

Restart Claude Desktop. When you see the hammer icon, the MCP server is connected.

Optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `REVIT_MCP_HOST` | `127.0.0.1` | Revit bridge host |
| `REVIT_MCP_PORT` | `8080` | Revit bridge port |
| `REVIT_MCP_CONNECT_TIMEOUT_MS` | `5000` | TCP connection timeout |
| `REVIT_MCP_COMMAND_TIMEOUT_MS` | `120000` | Per-command timeout |

## Supported Tools

| Tool | Description |
| ---- | ----------- |
| `get_revit_connection_status` | Check whether the local Revit bridge is reachable |
| `get_current_view_info` | Get current active view info |
| `get_current_view_elements` | Get elements from the current active view |
| `get_available_family_types` | Get available family types in current project |
| `get_selected_elements` | Get currently selected elements |
| `get_material_quantities` | Calculate material quantities and takeoffs |
| `ai_element_filter` | Intelligent element querying tool for AI assistants |
| `analyze_model_statistics` | Analyze model complexity with element counts |
| `create_point_based_element` | Create point-based elements (door, window, furniture) |
| `create_line_based_element` | Create line-based elements (wall, beam, pipe) |
| `create_surface_based_element` | Create surface-based elements (floor, ceiling, roof) |
| `create_grid` | Create a grid system with smart spacing generation |
| `create_level` | Create levels at specified elevations |
| `create_room` | Create and place rooms at specified locations |
| `create_dimensions` | Create dimension annotations in the current view |
| `create_structural_framing_system` | Create a structural beam framing system |
| `delete_element` | Delete elements by ID |
| `operate_element` | Operate on elements (select, setColor, hide, etc.) |
| `color_elements` | Color elements based on a parameter value |
| `tag_all_walls` | Tag all walls in the current view |
| `tag_all_rooms` | Tag all rooms in the current view |
| `export_room_data` | Export all room data from the project |
| `store_project_data` | Store project metadata in local database |
| `store_room_data` | Store room metadata in local database |
| `query_stored_data` | Query stored project and room data |
| `send_code_to_revit` | Send C# code to Revit to execute |
| `say_hello` | Display a greeting dialog in Revit (connection test) |

## Development

```bash
npm install
npm run build
```

## License

[MIT](https://github.com/BhaveshY/mcp-servers-for-revit/blob/main/LICENSE)
