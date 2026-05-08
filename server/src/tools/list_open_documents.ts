import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { withRevitConnection } from "../utils/ConnectionManager.js";

export function registerListOpenDocumentsTool(server: McpServer) {
  server.tool(
    "list_open_documents",
    "Lists the Revit documents currently open in the running Revit session, including title, path, and which one is active. Use this before multi-model workflows so the user knows which model to activate next.",
    {},
    async () => {
      try {
        const response = await withRevitConnection(async (revitClient) => {
          return await revitClient.sendCommand("list_open_documents", {});
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
        return {
          content: [
            {
              type: "text",
              text: `list_open_documents failed: ${
                error instanceof Error ? error.message : String(error)
              }`,
            },
          ],
        };
      }
    }
  );
}
