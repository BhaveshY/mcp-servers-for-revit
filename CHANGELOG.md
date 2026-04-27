# Changelog

Notable changes to mcp-servers-for-revit. Versioning follows the release tags.

## Unreleased — install report fix batch (2026-04-27)

This batch addresses every issue raised in the Windows install fix report
generated on 2026-04-27 from logs at `C:\Users\eb-a\.claude\projects\C--Users-eb-a-Downloads\`.
The branch was prepared on macOS and needs Windows verification before merging
to `main` (no `dotnet build` toolchain on macOS for `net48` + Revit-targeting
NuGets).

### Fixed

- **Misleading "Failed to create command instance" log on every healthy startup** — `plugin/Core/CommandManager.cs:171` was logging "Failed to create command instance" at `Info` level **after** a successful `RegisterCommand` call. The commands were loading correctly the whole time; the log just lied. The success path now reads "Registered command [name] from X" at `Info`. The actual catch path now logs full exception details (type, message, recursive `InnerException` chain, `StackTrace`, and `ReflectionTypeLoadException.LoaderExceptions` where applicable) at `Error` level so any real future failure is debuggable on first sight. Closes report Issue 1. *(commit `de40b55`)*

- **`ElementId` portability** — added `REVIT2025_OR_GREATER` and `REVIT2026_OR_GREATER` define constants to `commandset/RevitMCPCommandSet.csproj` and replaced ~35 ElementId-numeric-access call sites across `commandset/Services/` and `commandset/Utils/` with a single `RevitMCPCommandSet.Utils.ElementIdExtensions.GetIdValue()` helper that picks `IntegerValue` (R20–R23), `Value` (R24), or `GetValue()` (R25+) at compile time. Closes report Issue 2. *(commit `42273cb`)*

- **Windows install requires manual hand-holding** — added `scripts/install.ps1`, a single-shot idempotent installer that detects/installs Node.js LTS, Python 3.12, and .NET 8 SDK via winget; refreshes PATH from Machine + User scope so the running PowerShell process sees newly installed tools; builds and deploys the plugin into `%AppData%\Autodesk\Revit\Addins\<version>\`; runs `npm.cmd install && npm.cmd run build` in `server/`; registers the connector in `%UserProfile%\.claude.json`; and smoke-tests the stdio handshake. Closes report Issues 3 (PATH inheritance), 4 (Python missing for `better-sqlite3`), 5 (`npm.ps1` blocked by execution policy), and 6 (RevitAPI.dll on-disk probing). *(commit `1904b21`)*

### Added

- **`get_status` health-check tool** — built-in plugin endpoint and matching MCP tool. Answers synchronously without raising a Revit ExternalEvent (so it works while a schedule view is active). Returns `{ status, isRunning, port, revitVersion, initializedAtUtc, loadedCommands, failedCommands, activeView: { type, name } }`. Use it from Claude when a tool returns "Method not found" or to confirm readiness before issuing real tool calls. Closes report Issue 7. *(commit `f456ab0`)*

- **`ActiveViewGuard.RequireGraphicalView(uidoc, out string error)` helper** — for command handlers that need a floor plan / section / 3D view (the install report's chat noted commands "working better when a floor plan is open"). Returns a user-facing error naming the actual view type so the LLM can guide the user to switch views instead of returning an opaque Revit API exception. Applied as exemplar to `TagWallsEventHandler`. *(commit `d7f6a62`)*

### Documentation

- **README** — updated prerequisites to call out Python 3.x as a Windows requirement (`better-sqlite3` native build); added a Windows-specific notes block covering PowerShell execution policy, post-`winget` PATH refresh, and the `node.exe` / `npm.cmd` full-path pattern; added a "One-shot Windows install" section pointing to `scripts/install.ps1`; added an "Active view requirements" section documenting which tools need a graphical view; added `get_status` to the supported tools table.

### Intentionally not done

- **Newtonsoft.Json binding redirect (Issue 1's proposed fix)** — the report's binding-redirect proposal was built on top of the misdiagnosed "Failed to create command instance" log line. Both projects already `<PackageReference Include="Newtonsoft.Json" Version="13.0.3" />` (identical version) and net48 with PackageReference handles unification without an `app.config` redirect. Adding one for a problem that does not exist would just be cargo cult.
- **CI workflow (Section 7 of the report)** — Revit cannot run on GitHub-hosted Windows runners. A workflow that built only the server side would give false confidence; the failures the user actually hits are inside Revit's `AppDomain`.
