#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { registerTools } from "./tools/register.js";
import { closeRevitConnection } from "./utils/ConnectionManager.js";

const server = new McpServer(
  {
    name: "mcp-server-for-revit",
    version: "1.0.0",
  },
  {
    instructions:
      "Use this server for Autodesk Revit model inspection, BIM data extraction, element creation/modification, annotation, and Revit automation tasks. Start with get_revit_connection_status when Revit connectivity is uncertain. Prefer read-only tools for discovery before write/destructive tools. Keep model-query limits focused to avoid oversized outputs in Claude Code.",
  }
);

async function main() {
  await registerTools(server);

  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Revit MCP server started");
}

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, async () => {
    closeRevitConnection();
    await server.close();
    process.exit(0);
  });
}

main().catch((error) => {
  console.error("Error starting Revit MCP Server:", error);
  process.exit(1);
});
