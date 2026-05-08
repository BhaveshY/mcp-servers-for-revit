const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");

const root = path.resolve(__dirname, "..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

test("say_hello is not exposed to Claude or loaded by the Revit command registry", () => {
  const registerSource = read("server/src/tools/register.ts");
  assert.match(registerSource, /DISABLED_TOOL_FILES/);
  assert.match(registerSource, /say_hello\.(ts|js)/);

  const commandConfig = JSON.parse(read("command.json"));
  const commandNames = commandConfig.commands.map((command) => command.commandName);
  assert.ok(!commandNames.includes("say_hello"));
});

test("connection manager retries socket startup failures with actionable English guidance", () => {
  const source = read("server/src/utils/ConnectionManager.ts");
  assert.match(source, /CONNECT_RETRY_DELAYS_MS\s*=\s*\[1000,\s*2000,\s*4000\]/);
  assert.match(source, /connect_to_revit_failed/);
  assert.match(source, /Add-Ins > mcp-servers-for-revit > Stop, then Start/);
  assert.doesNotMatch(source, /connect to revit client failed|连接到Revit客户端失败/);
});

test("list_open_documents is available end-to-end", () => {
  assert.ok(fs.existsSync(path.join(root, "server/src/tools/list_open_documents.ts")));
  assert.ok(fs.existsSync(path.join(root, "commandset/Commands/Access/ListOpenDocumentsCommand.cs")));
  assert.ok(fs.existsSync(path.join(root, "commandset/Services/ListOpenDocumentsEventHandler.cs")));

  const commandConfig = JSON.parse(read("command.json"));
  const commandNames = commandConfig.commands.map((command) => command.commandName);
  assert.ok(commandNames.includes("list_open_documents"));
});

test("send_code_to_revit reports timeouts and compile errors with stable English prefixes", () => {
  const commandSource = read("commandset/Commands/ExecuteDynamicCode/ExecuteCodeCommand.cs");
  const handlerSource = read("commandset/Commands/ExecuteDynamicCode/ExecuteCodeEventHandler.cs");

  assert.match(commandSource, /send_code_to_revit_timeout/);
  assert.match(commandSource, /timeoutMs\s*=\s*60000/);
  assert.match(handlerSource, /code_compile_error/);
  assert.match(handlerSource, /execution_failed/);
});
