import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { getRevitBridgeStatus } from "../utils/ConnectionManager.js";

export function registerGetRevitConnectionStatusTool(server: McpServer) {
  server.registerTool(
    "get_revit_connection_status",
    {
      title: "Get Revit Connection Status",
      description:
        "Check whether the local Revit add-in bridge is reachable. Use this before Revit operations when connection state is uncertain.",
      inputSchema: {},
      annotations: {
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false,
      },
    },
    async () => {
      const status = await getRevitBridgeStatus();

      return {
        content: [
          {
            type: "text",
            text: JSON.stringify(status, null, 2),
          },
        ],
        structuredContent: status,
      };
    }
  );
}
