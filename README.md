# Factorio AI Engineer 🏭🤖

[English](README.md) | [Русский](README.ru.md)

An autonomous AI agent playing **Factorio 2.0 (Space Age)** in real-time using Large Language Models (Gemini / OpenAI API / Local LLMs via Kobold.cpp).

Unlike pure computer-vision approaches, this project uses a high-precision **spatial coordinate system**, interactive environment scanning, and a hybrid task-queue architecture. The AI agent inspects surrounding entities, evaluates recipes and inventory, and constructs working automated production lines directly on the map.

---

## Architecture: Autonomous Companion Bot

The AI agent has been uncoupled from the player's character and migrated into a dedicated, autonomous in-game companion entity (`character`) with its own inventory and custom blue armor:

- **Autonomous Entity & Navigation:**
  - Operates without hijacking or locking the human player's controls or cursor.
  - Supports relative navigation and partner tracking via the native `walk_to_player` operation.
  - Telemetry observation includes both companion and human partner coordinates (`human_player`).

- **Task Queue & Asynchronous State Machine:**
  - **Manual Crafting (`CRAFTING`):** Monitored through `crafting_queue_size`; consecutive tasks (such as chest delivery) wait until the crafting queue is completely finished.
  - **Equipment (`EQUIPPING_ARMOR`):** Queued state prevents race conditions during multi-step chains like "take from chest -> equip".
  - **Smart Logistics (`MOVING_ITEMS`):** Automatic pathing to destination containers and furnaces prior to item transfer.

- **Construction & Deconstruction:**
  - Autonomous blueprint and ghost placement (`build_ghosts`) using materials directly from the companion's inventory.
  - Native resource extraction and structure dismantling respecting legitimate interaction ranges (`can_reach_entity` / `reach_distance`).

## 🌟 Key Features & Improvements

- **Spatial Coordinate Engine**: Custom mod operations (`walk_to(x, y)`, `place_entity(name, x, y, dir)`, `move_items(..., x, y)`) allowing sub-tile precision rather than blind target chasing.
- **Environment & Player Scanning (`scanEntities`)**:
  - Dynamic radar scan returning exact `(x, y)` world coordinates of nearby entities.
  - Automatically identifies and returns the player's position (`player.x`, `player.y`) to build relative structures ("east of my position").
  - Clustered resource filtering (condenses massive ore patches from 10k+ tokens down to compact reference points).
- **Factorio 2.0 Direction Standard**: Full support for 16-way entity orientation (North: `0`, East: `4`, South: `8`, West: `12`).
- **Autonomous Reasoning & Multi-step Queues**:
  - Automatically checks inventory and crafts missing dependencies before construction.
  - Queues sequential tasks (e.g., *Craft Furnaces -> Walk -> Place in a row -> Fuel with Coal*) via in-game tick events.
- **Safe Dynamic Entity Resolution**: Built-in translation for colloquial concepts (`tree`, `rocks`, `ore`, `enemy`) with fallback protection to prevent server crashes on unknown names.
- **Silent Operations (`/sc`)**: Clean in-game experience without command-echo spam in chat.
- **Fast Cloud & Local Model Support**: Works out of the box with Gemini 2.5 Flash / Flash-Lite via OpenAI-compatible API, as well as local Kobold.cpp / Ollama instances.

---

## 🏗️ Architecture

```
                 +---------------------------+
                 |   Player / In-Game Chat   |
                 +-------------+-------------+
                               | (Player messages / In-game events)
                               v
+------------------+   WebSocket   +--------------------+
| Factorio Mod     | <-----------> | factorio-wrapper   |
| (__autorio__)    |    (8080)     | (Node.js bridge)   |
+--------+---------+               +---------+----------+
         ^                                   |
         | RCON commands                     | Forward events
         v                                   v
+------------------+   HTTP POST   +--------------------+
| factorio-rcon-api| <-----------> | packages/agent     |
| (Docker bridge)  |    (24180)    | (TypeScript / LLM) |
+------------------+               +---------+----------+
                                             |
                                             v
                                   +--------------------+
                                   |  LLM Inference     |
                                   |  (Gemini / OpenAI) |
                                   +--------------------+
```

---

## 🚀 Quick Start Guide

### 1. Prerequisites
- **Factorio** (version 2.0+ recommended)
- **Node.js** (v22+ or v24+) with **pnpm**
- **Docker Desktop** (for the RCON HTTP gateway)

### 2. Install Mod
Copy the mod folder into your Factorio mods directory:
```cmd
xcopy /E /I packages\autorio C:\Games\FactorioHeadless\mods\autorio
:: Also copy to your game client mods folder:
xcopy /E /I packages\autorio %appdata%\Factorio\mods\autorio
```
*(Ensure no conflicting `autorio_*.zip` archives exist in the mods folder).*

### 3. Start RCON API Gateway (Docker)
Run the prebuilt Go RCON-to-HTTP container:
```bash
docker run --rm -it --name factorio-rcon-api \
  -e FACTORIO_RCON_HOST=127.0.0.1 \
  -e FACTORIO_RCON_PORT=27015 \
  -e FACTORIO_RCON_PASSWORD=your_rcon_password \
  -p 24180:24180 \
  factorio-rcon-api:local
```

### 4. Start Factorio Server & Wrapper
In the project root:
```bash
pnpm --filter ./packages/factorio-wrapper run dev
```

### 5. Configure & Start AI Agent
Create `packages/agent/.env.local`:
```env
OPENAI_API_KEY=your_api_key
# Examples:
# Gemini: [https://generativelanguage.googleapis.com/v1beta/openai/](https://generativelanguage.googleapis.com/v1beta/openai/)
# OpenRouter: [https://openrouter.ai/api/v1/](https://openrouter.ai/api/v1/)
# Local (Kobold.cpp): [http://127.0.0.1:5001/v1/](http://127.0.0.1:5001/v1/)
OPENAI_API_BASEURL=your_api_base_url

RCON_API_SERVER_PORT=24180
RCON_API_SERVER_HOST=127.0.0.1

FACTORIO_WS_PORT=8080
FACTORIO_WS_HOST=127.0.0.1
```

Start the agent:
```bash
cd packages/agent
pnpm dlx tsx --env-file=.env.local src/main.ts
```

---

## 💬 In-Game Example Commands

Connect to your local server (`127.0.0.1:34197`) and type in chat:

- **Environmental Awareness:**
  > *"Scan area with radius 10 and tell me what you see"*
- **Autonomous Construction & Crafting:**
  > *"Check my inventory. If I have less than 3 stone furnaces, craft what is needed. Then scan the area and place 3 stone furnaces in a row starting 2 tiles east of my position."*
- **Automated Production Cell:**
  > *"Place 1 burner mining drill at -76.5, -108.5 facing south, place 1 stone furnace at -76.5, -106.5, and put 5 coal into both."*
- **Targeted Resource Gathering:**
  > *"Cut 5 trees around you"*

---

## 📜 Credits & License
- Based on foundational research and mod bridge concepts from [moeru-ai/airi-factorio](https://github.com/moeru-ai/airi-factorio).
- Licensed under the [MIT License](LICENSE).