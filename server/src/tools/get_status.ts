import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { withRevitConnection } from "../utils/ConnectionManager.js";

/**
 * Health-check / readiness probe.
 *
 * Returns the plugin's command-load result, the Revit version it is running
 * against, and the active view type. Use this BEFORE calling any other Revit
 * tool when you suspect the plugin may not be ready yet, or to diagnose why
 * a tool returned "Method not found".
 *
 * Closes Issue 7 from the install report. Does not require the Revit external-
 * event loop, so it answers immediately even when a schedule is the active view.
 */
export function registerGetStatusTool(server: McpServer) {
  server.tool(
    "get_status",
    "Returns the Revit MCP plugin's readiness state: which commands loaded, which failed (with the failure reason), the Revit version, and the active view type. Call this when a tool unexpectedly returns 'Method not found' or when you need to confirm the plugin is fully connected before issuing other tool calls.",
    {},
    async () => {
      try {
        const response = await withRevitConnection(async (revitClient) => {
          return await revitClient.sendCommand("get_status", {});
        });
        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(response, null, 2),
            },
          ],
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [
            {
              type: "text",
              text:
                `Could not reach the Revit MCP plugin on localhost:8080. ` +
                `Open Revit, then click the Revit MCP Switch button on the ribbon ` +
                `to start the plugin's socket server, then retry.\n\nUnderlying error: ${message}`,
            },
          ],
        };
      }
    }
  );
}
