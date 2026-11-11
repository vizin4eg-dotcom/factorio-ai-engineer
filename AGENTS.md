# AGENTS.md

Notes for agents working in this repository. The detailed map is `PROJECT_AI_CONTEXT.md` — read it before touching the mod. `README.md` is aspirational and trails the Lua.

## What is live

| Path | Role |
| --- | --- |
| `packages/autorio/control.lua` | The Factorio 2.0 mod that actually runs. Hand-edited TSTL bundle (~3.6k lines). |
| `packages/agent` | TypeScript LLM agent: parses server stdout, calls the model, fires `/sc` and sensor HTTP calls. |
| `packages/factorio-wrapper` | Node bridge: runs the headless server, tails stdout into a WebSocket on :8080. |
| `packages/factorio-rcon-api` | Vendored Go RCON → HTTP bridge on :24180. Treat it as a pipe. |

`packages/autorio/src/**` is stale upstream TypeScript. It is not the source of truth.

## Hard rules

1. **Never run `tstl` (even with `--noEmit`: this version still emits), and never run the root `pnpm build` / `pnpm build:packages` locally.** `packages/autorio`'s build script is `tstl`; it regenerates `control.lua` from the stale TypeScript and deletes the companion. Its `typecheck` script is `tsc --noEmit`, which is safe. Edit the Lua bundle in its existing TSTL shape (`["control"] = function`, `____exports`, `task_manager:add_task`). Building is only safe on a throwaway checkout (CI does it).
2. **After a Lua edit**: `.\sync_mod.ps1`, then `/sc game.reload_mods()` or restart the server. Reload disconnects the session — say so. `sync_mod.ps1` copies `control.lua` and `info.json`; a mod folder without `info.json` will not load.
3. **Two remote interfaces**: `autorio_operations` enqueues work and returns immediately (the host ignores the return value); `autorio_tools` prints JSON via `rcon.print`, and that output is the only channel back to the model. Sensors belong in `tools.ts`; actions belong in `prompt.md` + operations.
4. **Failures must be visible**: the agent reacts only to `log("[AUTORIO] [ERROR] ...")` lines. `game.print` never reaches stdout (verified against real server logs). Every new abort path logs exactly one such line — never per tick, and never a silent `reset_task_state()`.
5. **Multi-tick behavior needs all four pieces**: a `TaskStates` value, a `next_task` branch, a `state_*` function, and an `on_tick` `elseif`. Missing one leaves the task stuck out of `IDLE` and the queue deadlocks. `walk_to_entity` additionally needs `on_script_path_request_finished` and the 600-tick timeout; keep them together.
6. **Do not extend the known debts**: no new camelCase remote aliases (fix the caller), no layout/spacing rules in `prompt.md` (spacing lives next to the Lua prototype), no prompt instructions for numbers Lua can measure itself.

## Secrets and local config

- Never commit API keys, RCON passwords, or LAN IPs. They live in `packages/agent/.env.local` and `packages/factorio-wrapper/.env.local` (gitignored) or in the environment.
- `.gitignore` ignores `.env.*` except `.env.example`; keep the examples current.
- `start_all.ps1` reads `FACTORIO_RCON_PASSWORD` and `FACTORIO_RCON_HOST` from those files. Do not hardcode them back into scripts or docs.
- Machine-specific paths (`C:\Games\FactorioHeadless`, `%APPDATA%\Factorio`) are real for this setup. Do not invent another install layout.

## Verification

There is no Lua test harness.

- Agent types: `pnpm --filter @vizin4eg/factorio-agent typecheck`.
- Agent tests: `cd packages/agent && pnpm exec vitest run`.
- Lint: `pnpm lint` (repo). The pre-commit hook runs `pnpm lint-staged && pnpm typecheck`.
- Lua syntax: parse the file with a Lua 5.2 parser before syncing, then reload and watch for `[AUTORIO] [ERROR]`.
- One live call: use the RCON probe in `PROJECT_AI_CONTEXT.md` (“How to add a behavior”). If the bridge is down, say so — never claim a passing test.
- PowerShell: `[System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)`.

CI (`.github/workflows/ci.yml`) runs ESLint and TypeScript typecheck. It does not test Lua.

## Style

- Conventional commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`, optional scope (`fix(mod):`).
- Game-facing text and companion chat are Russian; code/comments mix English and Russian — match the file you are editing.
- `README.md` and `README.ru.md` are kept in sync; update both when user-facing behavior changes.
