import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { registerAIElementFilterTool } from "./ai_element_filter.js";
import { registerAnalyzeModelStatisticsTool } from "./analyze_model_statistics.js";
import { registerColorElementsTool } from "./color_elements.js";
import { registerCreateDimensionsTool } from "./create_dimensions.js";
import { registerCreateGridTool } from "./create_grid.js";
import { registerCreateLevelTool } from "./create_level.js";
import { registerCreateLineBasedElementTool } from "./create_line_based_element.js";
import { registerCreatePointBasedElementTool } from "./create_point_based_element.js";
import { registerCreateRoomTool } from "./create_room.js";
import { registerCreateStructuralFramingSystemTool } from "./create_structural_framing_system.js";
import { registerCreateSurfaceBasedElementTool } from "./create_surface_based_element.js";
import { registerDeleteElementTool } from "./delete_element.js";
import { registerExportRoomDataTool } from "./export_room_data.js";
import { registerGetAvailableFamilyTypesTool } from "./get_available_family_types.js";
import { registerGetCurrentViewElementsTool } from "./get_current_view_elements.js";
import { registerGetCurrentViewInfoTool } from "./get_current_view_info.js";
import { registerGetMaterialQuantitiesTool } from "./get_material_quantities.js";
import { registerGetRevitConnectionStatusTool } from "./get_revit_connection_status.js";
import { registerGetSelectedElementsTool } from "./get_selected_elements.js";
import { registerOperateElementTool } from "./operate_element.js";
import { registerQueryStoredDataTool } from "./query_stored_data.js";
import { registerSayHelloTool } from "./say_hello.js";
import { registerSendCodeToRevitTool } from "./send_code_to_revit.js";
import { registerStoreProjectDataTool } from "./store_project_data.js";
import { registerStoreRoomDataTool } from "./store_room_data.js";
import { registerTagAllRoomsTool } from "./tag_all_rooms.js";
import { registerTagAllWallsTool } from "./tag_all_walls.js";

const toolRegistrars = [
  registerGetRevitConnectionStatusTool,
  registerGetCurrentViewInfoTool,
  registerGetCurrentViewElementsTool,
  registerGetSelectedElementsTool,
  registerGetAvailableFamilyTypesTool,
  registerAIElementFilterTool,
  registerAnalyzeModelStatisticsTool,
  registerGetMaterialQuantitiesTool,
  registerExportRoomDataTool,
  registerCreatePointBasedElementTool,
  registerCreateLineBasedElementTool,
  registerCreateSurfaceBasedElementTool,
  registerCreateGridTool,
  registerCreateStructuralFramingSystemTool,
  registerCreateRoomTool,
  registerCreateLevelTool,
  registerCreateDimensionsTool,
  registerOperateElementTool,
  registerColorElementsTool,
  registerDeleteElementTool,
  registerTagAllWallsTool,
  registerTagAllRoomsTool,
  registerStoreProjectDataTool,
  registerStoreRoomDataTool,
  registerQueryStoredDataTool,
  registerSendCodeToRevitTool,
  registerSayHelloTool,
];

export async function registerTools(server: McpServer) {
  for (const registerTool of toolRegistrars) {
    registerTool(server);
  }
}
