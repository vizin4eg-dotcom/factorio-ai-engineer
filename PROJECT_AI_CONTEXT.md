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
| `packages/autorio/control.lua` | **The mod.** Hand-edited TSTL bundle, ~4260 lines. This is what the game runs. |
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

Body: `equip_armor(name?)`, `equip_module(name, count?, x?, y?)`, `remove_module(name, count?, x?, y?)`, `enter_vehicle(name?)`, `drive_to(x, y)`, `exit_vehicle()`, `attack_nearest_enemy(radius?)`.
`equip_module` / `remove_module` really move equipment now: they share `equipment_grid_equip` / `equipment_grid_unequip` with the `manage_armor_grid` tool, remove the item from the main inventory on equip, and insert it back on unequip. A failure (unknown item, no armor grid, no free space) logs one `[AUTORIO] [ERROR] equip_module` / `remove_module` line. `x` and `y` are optional grid coordinates; omitted means auto-place.

Advisor: `start_advisor()`, `stop_advisor()`, `factory_report()`. Lua counts and `game.print`s one line. The model does not invent rates and leaves `chatMessage` empty.

Tagging shim: `tagSelectedEntity(label, category)` forwards to `autorio_tools.tag_selected_entity`. The prompt currently emits the camelCase shim. That is debt, not a style to extend.

There is a second set of camelCase aliases (`enterVehicle`, `driveTo`, `equipModule`, `startAdvisor`, ...). They exist because the model was emitting the tool name into `operationCommands`. Do not add more aliases. Fix the caller.

Directions are Factorio 2.0 16-way: N=0, E=4, S=8, W=12. `parse_direction` also accepts `"north"` / `"south"` / `"east"` / `"west"`. Prefer the words in the prompt.

### autorio_tools (live names)

`scan_entities(radius, player_id)`, `get_inventory_items(player_id)`, `get_base_telemetry(player_id)`, `get_recipe(item, player_id)`, `tag_selected_entity(label, category, player_id)`, `get_main_base_footprint()`, `get_main_base_threats(max_distance)`, `manage_armor_grid(action, equipment_name, count, x, y, enabled)`, `manage_personal_logistics(action, item_name, min_count, max_count)`.

`manage_armor_grid` actions: `inspect` (grid width/height, every module with `x`/`y`/energy/shield, totals, personal roboport count, `construction-robot`/`logistic-robot` in the main inventory, `allow_dispatching_robots`), `equip`, `unequip` (`"all"` strips the grid), `toggle_roboport` (forces `enabled` when passed). `manage_personal_logistics` actions: `status` (network coverage, available construction/logistic robots, nearest roboport outside coverage, requests, trash), `set_request`, `clear_request`. Both print one JSON object via `rcon.print`; the host tools return it verbatim. They are one-tick calls: no task state, no queue.

Factorio 2.0 API notes (verified live on 2.0.77 against the companion, unit 145581):
- `grid.put{name = ..., position = {x, y}}` creates equipment and **does not consume any inventory** — the caller removes the item. Omitting `position` auto-places. It returns `LuaEquipment` or an error.
- `grid.take{name = ..., position = {x, y}}` returns the item stack; `{equipment = <LuaEquipment>}` is rejected ("Equipment or position not specified").
- `grid.get_contents()` gives `{name, count, quality}`; `LuaEquipment` has `energy`, `max_energy`, `shield`, `max_shield`, `position`, `quality` (a prototype).
- `character.allow_dispatching_robots` is the only personal-roboport switch; there is no per-equipment toggle. `defines.inventory.character_robots` does not exist in 2.0 — personal construction robots are counted in the main inventory.
- Personal logistics: `character.get_requester_point()` → `LuaLogisticPoint`; `sections_count`, `get_section(1)` → `LuaLogisticSection` with `filters`, `set_slot(i, filter)`, `clear_slot(i)`, `get_slot(i)`. The filter shape is `{value = {type = "item", name = ..., quality = "normal"}, min = n, max = n?}` — a top-level `{name = ...}` is silently stored as an empty filter. A filter set with only `min` reads back without `max` (no auto-trash). `character_personal_logistic_requests_enabled` exists on `LuaPlayer`, not on a character entity, so the companion has no such flag.
- Coverage comes from `surface.find_logistic_network_by_position(bot.position, bot.force)`; `point.logistic_network` may be an invalid object while out of range. `defines.inventory.character_trash` (8) still exists for the trash contents.

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

Local `HEAD` is `44d99df` (2026-11-11), a merge of `origin/main` `daf52a6` into the hardened branch. Upstream already implemented armor/vehicle calls, the drive/follow loop, the factory advisor and `scan_patch`/`mine_patch`; the hand-edited bundle had its own versions plus the pathfinding-event fix, the `[ERROR]` channel, the single-craft flow and main-base defense. Conflicts were resolved by keeping the hardened behavior and taking upstream's vehicle search radius 120. Keep the bundle hand-edited; never rebuild it with `tstl`.

The tree is clean as of `44d99df`; the previously dirty `prompt.md`, `tools.ts`, `message-handler.ts`, `metrics.ts` and this file are committed. `start_all.ps1` no longer stores the RCON password or a LAN IP; both come from `packages/agent/.env.local` (`FACTORIO_RCON_PASSWORD`, `FACTORIO_RCON_HOST`). Do not put them back into the script or docs.

## What changed locally on 2026-11-10

- `walk_to_entity` had no `on_script_path_request_finished` handler, so it deadlocked the queue forever. The handler is back, and a 600-tick timeout covers a lost reply.
- `CRAFTING` called `begin_crafting` twice (once in `next_task`, once in `state_crafting`), doubling the requested amount. Only `state_crafting` starts the craft now.
- All aborting states emit `[AUTORIO] [ERROR]` (32 sites), so the agent can see failures it previously only heard about in-game.
- `equip_module` was a stub: `state_equipping_module` only printed a message, and upstream was the same. Fixed on 2026-11-11 (see below).

## What changed locally on 2026-11-11

- The anti-stuck code in `on_tick` was dead: `state_walking_direct` (and every other state) re-aimed `walking_state` at the target in the same tick, overwriting the rotation. It now only accumulates `storage.stuck_dir_offset`; `apply_stuck_offset(bot)` runs after the state dispatch (and in the follow branch), so the 45° detour survives.
- The stuck detector measures displacement over a 20-tick window, not per tick: slow sliding along a wall used to count as "standing still", so the offset was advanced every 20 ticks and the companion visibly spun in place. Now it rotates 45° only when the window moved < 0.5 tiles, keeps the offset while sliding (0.5–2.5), and clears it after 2.5+ tiles. For `WALKING_DIRECT` / `WALKING_TO_ENTITY` a full second of zero movement aborts the task with one `[ERROR] movement blocked` line instead of spinning; follow/idle never accumulate an offset.
- `walk_to` has a no-progress timeout: if the distance to the target does not shrink for 20 s, it logs one `[AUTORIO] [ERROR] walk_to: no progress ...` line, prints to the player, and advances the queue. Verified live: the companion was previously stuck on a tree forever; with the fix it walks around, and it aborts cleanly on a roboport centre.
- `walk_to_entity` sent `goal = entity.position`; for a multi-tile building (roboport, chest, drill) that centre is not walkable. The goal is now `find_non_colliding_position("character", entity.position, 32, 0.5)` and the path's `bounding_box` comes from `bot.prototype.collision_box` (0.4 × 0.4). The old hardcoded 1 × 1 box did not fit next to rail signals and buildings, so `request_path` answered "no path" even on open ground.
- Path replies with `try_again_later` used to be treated as "no path" and aborted the task. They now retry every 15 ticks (up to 60 times).
- `request_path` refuses to cross the rail lines (the pathfinder treats them as blocking), although the character walks over rails fine. On "no path" the task now turns into `WALKING_DIRECT` toward the walkable goal tile, keeping the 20 s no-progress guard, so the companion still reaches a roboport across the tracks. The "train" layer was dropped from the collision mask too.
- `walk_to(x, y)` now goes through the same pathfinder as `walk_to_entity`: a new `WALKING_TO_POINT` task requests a path to the walkable tile nearest `(x, y)` and follows it, so buildings are walked around instead of being bumped into. If the pathfinder refuses (rails), the shared fallback turns it into `WALKING_DIRECT` with the usual 20 s no-progress guard. `WALKING_TO_POINT` needs the same four pieces as any state: `TaskStates`, the `next_task` branch, `state_walking_to_point`, and the `on_tick` `elseif`.
- `follow_player` was sticky: `storage.is_following` lived in the save, so after a reload the companion silently chased the player and fought every movement task. `setup()` now clears it; follow is opt-in per session and must be re-asked after a reload.
- Live verification 2026-11-11: tree detour + arrival, 20 s stall abort with the queue moving on to `craft_item`, `walk_to_entity("roboport")` across the rails via the direct fallback, and the companion standing still 29 tiles from the player after the follow reset.
- Armor grid and personal logistics are real now. `state_equipping_module` calls `equipment_grid_equip` / `equipment_grid_unequip`: the module leaves the main inventory on equip and returns on unequip, with one `[AUTORIO] [ERROR]` line on failure. `equip_module` / `remove_module` accept optional `x` / `y` grid coordinates. The camelCase aliases delegate to them instead of carrying a second copy.
- New `autorio_tools` methods `manage_armor_grid` and `manage_personal_logistics` (backed by the `manageArmorGrid` / `managePersonalLogistics` tools in `tools.ts`, flat schemas) inspect and change both systems in one tick. `prompt.md` gained section 14 for personal logistics and points section 9 at the inspect/toggle tool.
- `tools.test.ts` enforces that every tool schema stays flat and pins the two new tools' actions and parameter names.
- Live API verification 2026-11-11 (before the feature commit): `grid.put`/`take`, `get_contents`, `get_requester_point`/`get_section`/`set_slot`/`get_slot`/`clear_slot`, `allow_dispatching_robots`, `find_logistic_network_by_position`, `character_trash`.
- Live runtime check after the server restart (2.0.77, companion unit 145581, `power-armor` 6 × 8): `inspect` returned the grid, `equip energy-shield` moved the item out of the inventory (2 → 1) and `unequip` put it back (1 → 2), `toggle_roboport` flipped `allow_dispatching_robots` both ways, `status` reported `in_network: false` with the nearest roboport at `(178, -241)`, `set_request iron-plate 50/100` was read back by `status` and `clear_request` removed it, an unknown item returned `ok: false`. The queued path logged `Companion equipped 1 x energy-shield`, `[ERROR] equip_module unobtainium: unknown equipment` and `Companion removed 1 x energy-shield ...`, with `All operations completed` each time.

## What not to spend a session on

- More verbs (another vehicle, another equipment slot, another chat synonym). Follow, tank, armor grid, and advisor already exist.
- More layout rules in `prompt.md`. Spacing belongs next to the entity prototype in Lua.
- Porting the bundle back to TypeScript before two layout macros survive a reload.
- Editing `packages/factorio-rcon-api` to change game behavior. It is a pipe.
