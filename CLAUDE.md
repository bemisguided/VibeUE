# VibeUE Plugin — Claude Code Guide

## What this is

VibeUE is an Unreal Engine editor plugin that exposes engine internals to Python via a set of
static C++ service classes. A companion MCP server bridges those Python services to AI assistants,
allowing an AI to read and modify Unreal assets (Blueprints, materials, data tables, etc.) while
the editor is running.

Target engine version: **UE 5.7**

## Repository layout

```
Source/VibeUE/
  Public/PythonAPI/     — UCLASS service headers (one per domain)
  Private/PythonAPI/    — service implementations
  Public/MCP/           — MCP server and tool registration
  Private/MCP/
  Public/Tools/         — internal editor tool helpers
  Private/Tools/
Content/
  Help/                 — per-tool markdown docs surfaced via manage_skills
  instructions/         — AI system prompt (vibeue.instructions.md)
  Python/               — vibeue-proxy.py (MCP bridge)
```

## Service architecture

Every service is a `UCLASS(BlueprintType)` with only `static UFUNCTION(BlueprintCallable)`
methods. Python sees them as class-level methods:

```python
import unreal
unreal.BlueprintService.list_variables("/Game/BP_Player")
```

C++ out-parameters (`FString& OutValue`, `FMyStruct& OutInfo`) become Python return values —
Python callers receive a tuple `(bool, value)` when there is a single out-param, or just the
collection type when the method returns a `TArray`.

Return types must be UCLASS/USTRUCT/primitive — raw C++ types not reflected by UHT will not be
visible to Python.

## Adding a new service method

1. **Declare** in the appropriate `Public/PythonAPI/U*Service.h`:
   - Mark `UFUNCTION(BlueprintCallable, Category = "VibeUE|Domain")`
   - Write the Python usage example in the doc-comment; agents read these at runtime via
     `discover_python_class`
   - Prefer `FString` over `FName` for parameters that come from Python callers

2. **Implement** in the matching `Private/PythonAPI/U*Service.cpp`:
   - Load the asset first (`LoadBlueprint`, `StaticLoadObject`, etc.) and return early on failure
   - Log with `UE_LOG(LogTemp, ...)` — agents surface these via `read_logs`
   - Call `FBlueprintEditorUtils::MarkBlueprintAsStructurallyModified` + `CompileBlueprint` after
     any structural change; skip compilation for read-only operations

3. **Test** by running the Python expression in `execute_python_code` with the editor open

## Feature development workflow

Features are developed on dedicated branches and merged into the fork tracking branch.

```
master                    (upstream base, never commit directly)
├── feat/<name>           (feature branch cut from master)
└── fork/last-november    (fork tracking branch — receives merges)
```

Steps:
1. `git checkout -b feat/<name> master`
2. Implement and commit on the feature branch
3. Push: `git push origin feat/<name>`
4. Merge into the fork: `git checkout fork/last-november && git merge --no-ff feat/<name>`
5. Force-push the fork: `git push --force-with-lease origin fork/last-november`

When rebasing the fork onto a new master tip, squash any intermediate fixup commits on feature
branches first so the fork history stays linear and readable.

## Design principles

### Research UE headers before coding

Never assume an API exists. Check the engine source at
`/Users/Shared/Epic Games/UE_5.7/Engine/Source/` before designing any feature that touches
internal editor types. Key headers for blueprint/component work:

- `Runtime/Engine/Classes/Engine/InheritableComponentHandler.h` — `FComponentKey`,
  `UInheritableComponentHandler`
- `Runtime/Engine/Classes/Engine/Blueprint.h` — `UBlueprint`, `GetInheritableComponentHandler`
- `Runtime/Engine/Classes/Engine/BlueprintGeneratedClass.h`
- `Runtime/Engine/Classes/Engine/SimpleConstructionScript.h` / `SCS_Node.h`
- `Editor/UnrealEd/Public/Kismet2/BlueprintEditorUtils.h`
- `Editor/UnrealEd/Public/Kismet2/ComponentEditorUtils.h` — `GetPropertyForEditableNativeComponent`

### Replicate editor constraints, don't bypass them

If the Blueprint Editor enforces a constraint (e.g. native components are only editable when their
property is `CPF_Edit`), the API should enforce the same constraint and log a clear message when
it rejects a call. This prevents silent failures that only appear at runtime or packaging.

### Strategy cascade for resolution

When an input can be satisfied by multiple sources (asset paths, short names, native classes, etc.)
use a numbered strategy cascade with `UE_LOG` on each successful non-obvious resolution path:

```cpp
// Strategy 1: most specific / cheapest
// Strategy 2: broader lookup
// Strategy 3: fallback scan
// Log on success so callers can see which path was taken
```

See `AddInterface` in `UBlueprintService.cpp` for a four-strategy example.

### Read vs. write component access

Components on a Blueprint can come from three sources with different write semantics:

| Source | Read | Write mechanism |
|--------|------|----------------|
| Local SCS node | `Node->ComponentTemplate` | Direct (always writable) |
| Inherited parent blueprint SCS node | `InheritableComponentHandler::GetOverridenComponentTemplate` or parent's template | `InheritableComponentHandler::CreateOverridenComponentTemplate` — creates a child-level override record |
| Inherited native C++ component | CDO sub-object via `GetObjectsWithOuter` | Direct on CDO sub-object; enforce `CPF_Edit` constraint via `FComponentEditorUtils::GetPropertyForEditableNativeComponent` |

The canonical implementation of this is the `FindComponentForRead` / `FindOrCreateWritableTemplate`
helper pair in `UBlueprintService.cpp`. Use this as the model for any other service that needs to
reach inherited components.

`UInheritableComponentHandler` only supports SCS-node components (`FComponentKey` takes a
`USCS_Node*`). There is no `FComponentKey` constructor for native C++ components — those go
through the Blueprint CDO directly.

### Keep helpers file-scoped

Shared logic used only within one `.cpp` file should be a `static` free function above the first
caller, not a private method on the service class. This avoids UHT noise and keeps the header
clean.

## Build notes

`UnrealEd` is a private dependency (`VibeUE.Build.cs`) — editor-only headers from
`Editor/UnrealEd/Public/` are available in all service implementations.

Rebuilding after a header change: open the project in the editor or run UBT directly; there is no
hot-reload for plugin source changes.

## Python API gotchas

- UE struct fields are accessed by **snake_case attribute** in Python, not `.get()`:
  `node.node_title`, not `node.get('node_title')`
- Method names in Python are the snake_case form of the C++ `PascalCase` name:
  `GetNodesInGraph` → `get_nodes_in_graph`
- `list_nodes` and `get_graph_nodes` do not exist — the correct method is `get_nodes_in_graph`
- Methods that return `TArray<FMyStruct>` return a Python list of struct objects, not dicts
