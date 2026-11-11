# Factorio AI Engineer — working context

Local checkout: `C:\Temp\Ai\airi-factorio`. Remote: `https://github.com/vizin4eg-dotcom/factorio-ai-engineer`. This file is for a model that can read the code. It is a map and a contract, not a cage. If it disagrees with `packages/autorio/control.lua`, the Lua wins — then fix this file.

## What is live

A headless Factorio 2.0 server runs a companion `character` (own inventory, not the human's cursor). The human talks in chat. The agent turns that into `remote.call`s. Lua queues work and advances it on `on_tick`.

```
human chat
  -> Factorio stdout
  -> packages/factorio-wrapper  (WebSocket :8080, tails the server process)
  -> packages/agent             (LLM; also speaks and acts over HTTP)
  -> packages/factorio-rcon-api (HTTP :24180 -> RCON :27015)
  -> /sc remote.call(...)
  -> packages/autorio/control.lua
```

`factorio-wrapper` is not the HTTP API. Port 24180 is `factorio-rcon-api`, a Go process, usually the `factorio-rcon-api:local` container. The game and the container are different network namespaces: the container must be pointed at a host address that reaches RCON, not at its own `127.0.0.1`. That address and the password live in `start_all.ps1` and the `.env.local` files. Do not copy them into docs, prompts, or commits.

Launch path that this machine actually uses: `start_all.ps1` (save picker, wrapper, docker RCON, agent). Mod install path that this machine actually uses: `sync_mod.ps1`. It copies **only** `packages/autorio/control.lua` to:

- `C:\Games\FactorioHeadless\mods\autorio\control.lua`
- `C:\Games\Factorio\mods\autorio\control.lua`
- `%APPDATA%\Factorio\mods\autorio\control.lua`

Do not invent a fourth install. Do not assume a vanilla Factorio layout.

## Source of truth

| Path | Status |
| --- | --- |
| `packages/autorio/control.lua` | **The mod.** Hand-edited TSTL bundle, ~3610 lines. This is what the game runs. |
| `packages/autorio/src/**` | Upstream `airi-factorio` player-bot. Stale. No companion, no ghosts, no vehicles, no advisor. |
| `packages/agent/src/llm/prompt.md` | Language → `operationCommands`. Must name Lua methods that exist. |
| `packages/agent/src/llm/tools.ts` | Host-side tool calls. Sensors belong here. Actions mostly should not. |
| `packages/agent/src/llm/message-handler.ts` | Turn loop: prefetch observation, call model, parse JSON. |
| `README.md` | Aspirational. Trails the Lua. |

**Never run `tstl` / `pnpm --filter @vizin4eg/autorio build`.** It regenerates `control.lua` from the stale TypeScript and deletes the companion. Hot reload in the bundle is a stub (`hot_reload` returns `{}`). After a Lua edit: `sync_mod.ps1`, then `/sc game.reload_mods()` or a server restart. Reload kicks the session; say so.

`control.lua` is still shaped like a TSTL bundle (`["control"] = function...`, `____exports`, `task_manager:add_task`). Edit inside that shape. Do not "clean it up" into handwritten modules in the same change as a feature. A later port back to TypeScript is a project of its own, and only worth it after the Lua macros are stable.

## Two remote interfaces

Actions — `remote.call("autorio_operations", name, ...)`. They enqueue and return immediately. The host fires them as one `/sc` string and **does not read the return value**.

Sensors — `remote.call("autorio_tools", name, ...)`. They `rcon.print` JSON. The HTTP response `output` is the only channel back to the agent. Print JSON, not prose.

`storage` is the right place for flags that must survive a tick (`is_following`, `advisor_enabled`, `monitored_nodes`, `evasion_ticks`). Do not invent a parallel global. Do not read `storage` from a remote call to "debug" it into chat on every turn.

### autorio_operations (live names)

Navigation: `walk_to(x, y)`, `walk_to_player()`, `walk_to_entity(name, radius)`, `follow_player()`, `cancel_all_tasks()`.
`cancel_all_tasks` also clears follow. A bare "стой" is this, not `stop_advisor`.
`walk_to_entity` is the only caller of `request_path`; it relies on the `on_script_path_request_finished` handler and the `path_request_tick` timeout in `state_walking_to_entity`. Keep all three together.

World: `mine_entity(name, count?)`, `place_entity(name, x, y, direction)`, `move_items(item, entity, max_count, to_entity, x, y)`, `build_ghosts(radius?, max_count?)`, `deconstruct_area(radius?)`, `craft_item(name, count)`, `wait(ticks)`.

Body: `equip_armor(name?)`, `equip_module(name, count?)`, `remove_module(name, count?)`, `enter_vehicle(name?)`, `drive_to(x, y)`, `exit_vehicle()`, `attack_nearest_enemy(radius?)`.
`equip_module` / `remove_module` are stubs in this bundle: `state_equipping_module` only reports `[ERROR]`. Port the upstream `c159853` implementation instead of inventing one.

Advisor: `start_advisor()`, `stop_advisor()`, `factory_report()`. Lua counts and `game.print`s one line. The model does not invent rates and leaves `chatMessage` empty.

Tagging shim: `tagSelectedEntity(label, category)` forwards to `autorio_tools.tag_selected_entity`. The prompt currently emits the camelCase shim. That is debt, not a style to extend.

There is a second set of camelCase aliases (`enterVehicle`, `driveTo`, `equipModule`, `startAdvisor`, ...). They exist because the model was emitting the tool name into `operationCommands`. Do not add more aliases. Fix the caller.

Directions are Factorio 2.0 16-way: N=0, E=4, S=8, W=12. `parse_direction` also accepts `"north"` / `"south"` / `"east"` / `"west"`. Prefer the words in the prompt.

### autorio_tools (live names)

`scan_entities(radius, player_id)`, `get_inventory_items(player_id)`, `get_base_telemetry(player_id)`, `get_recipe(item, player_id)`, `tag_selected_entity(label, category, player_id)`.

`player_id` 1 is the human. Scans and inventory for the companion go through `get_companion_body()`, not through that id. Passing 1 does not mean "scan the human".

`scan_entities` already collapses trees, rocks, and ore (at most two tiles per ore name). It also embeds a second copy of power / boiler / bot telemetry. `get_base_telemetry` computes the same things again, plus `named_nodes`. Do not add a third copy.

## One chat turn

1. Wrapper forwards a stdout line.
2. `parser.ts` classifies `[CHAT]`, `[AUTORIO] [ERROR]`, or `[AUTORIO] All operations completed`. Anything else is ignored. `game.print` is **not** a completion signal. `log("[AUTORIO] ...")` is, if it matches those two patterns exactly. Keep that spelling if you want the agent to notice.
3. On chat, the handler prefetches `scan_entities(25)` (which already embeds power / boiler / bot telemetry) and appends it to the user message. Inventory, footprint and threats are tool calls, not prefetched.
4. Model replies with JSON: `plan`, `currentStep`, `chatMessage`, `operationCommands[]`. No markdown fence. `parseLLMMessage` is a bare `JSON.parse`.
5. Host `game.print`s `chatMessage`, then joins `operationCommands` with `;` into one `/sc`.

Consequences:

- An action's failure is visible only if Lua `log`s an `[AUTORIO] [ERROR]`. Returning `{false, "reason"}` from a remote method is invisible to the agent.
- `game.print` does not reach stdout — confirmed against the real `factorio-current.log`: the advisor's `game.print` line is absent while its `log` line is present. So `[AUTORIO] [ERROR]` is the only failure channel the agent has. Every aborting state emits one (32 call sites); keep that convention — one line per failure, never per tick, and never a silent `reset_task_state()`.
- `[AUTORIO] All operations completed` starts another LLM turn with no check that a plan remains. An empty plan must return `operationCommands: []` or this loops.
- `messages` grows without bound. A long session will drown the prompt.
- Tool round-trips (`maxRoundTrip: 3`) and `operationCommands` are two action channels. The prompt already says "do not also call a tool for the same action". Prefer not exposing the action as a tool at all.
- `getRecipe` and `scanEntities` in `tools.ts` used to destructure `{ parameters }` while the schema is flat. Fixed: every tool now reads top-level fields (`item`, `radius`). Keep new tools on the flat schema.
- Model id has one source of truth: `DEFAULT_MODEL` in `config.ts` (`deepseek/deepseek-v4.1-flash-1017`), overridden by `OPENAI_MODEL_NAME`. OpenRouter provider routing (`provider.order`, `allow_fallbacks`) lives in the `composeAgent` provider options, because `neuri.call()` forwards only `model` and `maxRoundTrip`.

## How to add a behavior

Spatial work is a Lua function. The model names the intent. It does not emit a coordinate list, and the prompt does not grow another spacing table.

1. Write one `autorio_operations` method that plans and enqueues (or, for a sensor, one `autorio_tools` method that `rcon.print`s JSON).
2. If it is multi-tick, add a `TaskStates` value in the bundle's types table, a branch in `next_task`, a `state_*` function, and one `elseif` in `on_tick`. Missing any one of those leaves the task stuck out of `IDLE`, and the queue never completes.
3. Missing items become ghosts (`build_ghosts` already knows how) or a single printed reason. Do not fail silently.
4. Wire the phrase in `prompt.md` to that one method. Do not also add a tool unless the host must read a return value before the next command.
5. If RCON is up, prove the method with one call before touching the prompt:

```powershell
(Invoke-RestMethod -Method Post -Uri "http://localhost:24180/api/v2/factorio/console/command/raw" -ContentType "application/json" -TimeoutSec 8 -Body '{"input":"<LUA>"}').output
```

Use `/sc` so the command is not echoed into chat. If the bridge is down, say so. Do not invent a passing test.

A one-tick remote call is fine when the work is "measure and place a layout". A task state is required when the companion must walk, craft, or wait. Do not poll `storage` from outside to fake a completion.

## Git, as of this writing

Local `HEAD` is `7935012` (2026-10-22). `origin/main` is `daf52a6` (2026-10-31), six commits ahead: `7b9eee0` (armor/vehicle calls), `a21e39c` (drive/follow loop), `c159853` (modules + tank), `c8cb064` (advisor), `2e82acd` (bare stop), `daf52a6` (scan/mine patch). The dirty working tree already contains hand-written versions of all of these, including `scan_patch`/`mine_patch`, plus the pathfinding-event fix and the `[ERROR]` channel, so it is not simply "behind". Do not `git pull` over it: `git diff origin/main -- packages/autorio/control.lua` first and merge by hand.

Also dirty/staged: `prompt.md`, `tools.ts`, `message-handler.ts`, `README.ru.md`, untracked `metrics.ts` and this file. `start_all.ps1` no longer stores the RCON password or a LAN IP; both come from `packages/agent/.env.local` (`FACTORIO_RCON_PASSWORD`, `FACTORIO_RCON_HOST`). Do not put them back into the script or docs.

## What changed locally on 2026-11-10

- `walk_to_entity` had no `on_script_path_request_finished` handler, so it deadlocked the queue forever. The handler is back, and a 600-tick timeout covers a lost reply.
- `CRAFTING` called `begin_crafting` twice (once in `next_task`, once in `state_crafting`), doubling the requested amount. Only `state_crafting` starts the craft now.
- All aborting states emit `[AUTORIO] [ERROR]` (32 sites), so the agent can see failures it previously only heard about in-game.
- `equip_module` is still a local stub (`state_equipping_module` reports `[ERROR]`); upstream `c159853` has the real implementation, so do not "fix" the stub — port the upstream one.

## What not to spend a session on

- More verbs (another vehicle, another equipment slot, another chat synonym). Follow, tank, armor grid, and advisor already exist.
- More layout rules in `prompt.md`. Spacing belongs next to the entity prototype in Lua.
- Porting the bundle back to TypeScript before two layout macros survive a reload.
- Editing `packages/factorio-rcon-api` to change game behavior. It is a pipe.
