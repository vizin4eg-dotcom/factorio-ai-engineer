--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua (Enhanced for Companion Bot Architecture) ]]

local ____modules = {}
local ____moduleCache = {}
local ____originalRequire = require

local function get_target_player(player_id)
    if player_id then
        local p = game.get_player(player_id)
        if p and p.connected then return p end
    end
    if #game.connected_players > 0 then
        return game.connected_players[1]
    end
    return nil
end

local function get_companion_body()
    -- 1. Быстрый возврат валидной ссылки
    if storage.bot and storage.bot.valid then
        return storage.bot
    end

    local player = get_target_player(1)
    local default_force = (player and player.force) or "player"

    -- 2. Ищем существующего компаньона по ВСЕМ поверхностям (Наувис, Вулкан, платформы и т.д.)
    for _, surface in pairs(game.surfaces) do
        local chars = surface.find_entities_filtered{name = "character", force = default_force}
        for _, c in ipairs(chars) do
            -- Проверяем, что это не живой игрок
            if c.valid and (not player or c ~= player.character) then
                storage.bot = c
                return storage.bot
            end
        end
    end

    -- 3. Если бота нет ни на одной планете — создаём нового рядом с игроком
    if not player or not player.surface then return nil end

    storage.bot = player.surface.create_entity{
        name = "character",
        position = {player.position.x + 2.5, player.position.y},
        force = player.force
    }
    storage.bot.color = {r = 0.15, g = 0.45, b = 0.95, a = 1}
    log("[AUTORIO] Companion body created on surface: " .. player.surface.name)
    return storage.bot
end

local function build_safe_entity_filter(target_name, center_pos, radius, force)
    local filter = {
        position = center_pos,
        radius = radius
    }
    
    if not target_name or target_name == "" then
        return nil
    end

    target_name = string.lower(target_name)

    -- 1. Dictionary of common categories and aliases
    if target_name == "tree" or target_name == "trees" or target_name == "wood" then
        filter.type = "tree"
        return filter
    end

    if target_name == "rock" or target_name == "rocks" or target_name == "boulder" or target_name == "stone-rock" then
        filter.type = "simple-entity"
        return filter
    end

    if target_name == "ore" or target_name == "resource" or target_name == "deposit" then
        filter.type = "resource"
        return filter
    end

    if target_name == "enemy" or target_name == "biter" or target_name == "spitter" then
        filter.force = "enemy"
        return filter
    end

    -- 2. Exact prototype check in Factorio database
    if prototypes.entity[target_name] then
        filter.name = target_name
        return filter
    end

    -- 3. Safe type verification using pcall
    local test_filter = {position = center_pos, radius = radius, type = target_name}
    local success, _ = pcall(function()
        game.surfaces[1].find_entities_filtered(test_filter)
    end)
    if success then
        return test_filter
    end

    return nil
end

local function require(file, ...)
    if ____moduleCache[file] then
        return ____moduleCache[file].value
    end
    if ____modules[file] then
        local module = ____modules[file]
        local value = nil
        if (select("#", ...) > 0) then value = module(...) else value = module(file) end
        ____moduleCache[file] = { value = value }
        return value
    else
        if ____originalRequire then
            return ____originalRequire(file)
        else
            error("module '" .. file .. "' not found")
        end
    end
end

____modules = {
["utils.inventory"] = function(...) 
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
local ____exports = {}
function ____exports.get_inventory_items(self, player_id)
    log("[AUTORIO] Getting inventory items for companion bot")
    local bot = get_companion_body()
    if not bot or not bot.valid then return {} end
    local main_inventory = bot.get_main_inventory()
    if not main_inventory then
        return {}
    end
    return __TS__ArrayMap(
        main_inventory.get_contents(),
        function(____, binding)
            return {name = binding.name, count = binding.count}
        end
    )
end
return ____exports
 end,

["types"] = function(...) 
local ____exports = {}
____exports.TaskStates = TaskStates or ({})
____exports.TaskStates.IDLE = "idle"
____exports.TaskStates.WALKING_TO_ENTITY = "walking_to_entity"
____exports.TaskStates.MINING = "mining"
____exports.TaskStates.PLACING = "placing"
____exports.TaskStates.PLACING_IN_CHEST = "placing_in_chest"
____exports.TaskStates.PICKING_UP = "picking_up"
____exports.TaskStates.CRAFTING = "crafting"
____exports.TaskStates.RESEARCHING = "researching"
____exports.TaskStates.WALKING_DIRECT = "walking_direct"
____exports.TaskStates.MOVING_ITEMS = "moving_items"
____exports.TaskStates.ATTACKING = "attacking"
____exports.TaskStates.WAITING = "waiting"
____exports.TaskStates.BUILDING_GHOSTS = "building_ghosts"
____exports.TaskStates.EQUIPPING_ARMOR = "equipping_armor"
return ____exports
 end,

["task_manager"] = function(...) 
local function __TS__ArraySetLength(self, length)
    if length < 0 or length ~= length or length == math.huge or math.floor(length) ~= length then
        error("invalid array length: " .. tostring(length), 0)
    end
    for i = length + 1, #self do
        self[i] = nil
    end
    return length
end
local ____exports = {}
local ____types = require("types")
local TaskStates = ____types.TaskStates

function ____exports.new_task_manager(self)
    local next_task, player_state, task_queue
    function next_task(self)
        if player_state.task_state ~= TaskStates.IDLE then
            log("[AUTORIO] Task state is not IDLE, will not execute next task")
            return
        end
        local task = table.remove(task_queue, 1)
        if not task then
            player_state.task_state = TaskStates.IDLE
            log("[AUTORIO] All operations completed")
            return
        end
        log("[AUTORIO] Next task: " .. task.type .. ", remaining in queue: " .. tostring(#task_queue))
        player_state.task_state = task.type
        repeat
            local switch_state = task.type
            if switch_state == TaskStates.WALKING_TO_ENTITY then
                player_state.parameters_walk_to_entity = task
                break
            elseif switch_state == TaskStates.WALKING_DIRECT then
                player_state.parameters_walking_direct = task
                break
            elseif switch_state == TaskStates.MINING then
                player_state.parameters_mine_entity = task
                break
            elseif switch_state == TaskStates.PLACING then
                player_state.parameters_place_entity = task
                break
            elseif switch_state == TaskStates.MOVING_ITEMS then
                player_state.parameters_move_items = task
                break
            elseif switch_state == TaskStates.BUILDING_GHOSTS then
                player_state.parameters_build_ghosts = task
                break
			elseif switch_state == TaskStates.EQUIPPING_ARMOR then
				player_state.parameters_equip_armor = task
				break
            elseif switch_state == TaskStates.CRAFTING then
                do
                    local bot = get_companion_body()
                    if not bot or not bot.valid then
                        log("[AUTORIO] No companion bot found for crafting")
                        player_state.task_state = TaskStates.IDLE
                        next_task(nil)
                        break
                    end

                    local recipe_to_craft = task.recipe_name or task.item_name
                    local count_to_craft = tonumber(task.count) or 1

                    local queued_count = bot.begin_crafting({
                        count = count_to_craft,
                        recipe = recipe_to_craft
                    })

                    if queued_count == 0 then
                        log("[AUTORIO] Cannot craft " .. tostring(recipe_to_craft) .. ": missing materials")
                        game.print("[AI Companion]: Not enough materials to craft " .. tostring(recipe_to_craft))
                        player_state.task_state = TaskStates.IDLE
                        next_task(nil)
                        break
                    end

                    -- Фиксируем задачу и даем 15 тиков буфера на появление в очереди движка
                    player_state.parameters_craft_item = {
                        recipe = recipe_to_craft,
                        count = queued_count,
                        warmup_ticks = 15
                    }
                    break
                end
            elseif switch_state == TaskStates.ATTACKING then
                player_state.parameters_attack_nearest_enemy = task
                break
            elseif switch_state == TaskStates.RESEARCHING then
                player_state.parameters_research_technology = task
                break
            elseif switch_state == TaskStates.WAITING then
                player_state.parameters_waiting = task
                break
            end
        until true
    end

    player_state = {task_state = TaskStates.IDLE}
    task_queue = {}

    local function add_task(self, task)
        task_queue[#task_queue + 1] = task
        log("[AUTORIO] Task added: " .. task.type .. ", queue length: " .. tostring(#task_queue))
        if #task_queue == 1 then
            next_task(nil)
        end
    end

    local function reset_task_state(self)
        local bot = get_companion_body()
        if bot and bot.valid then
            if #task_queue == 0 then
                bot.walking_state = {walking = false}
            end
        end
        player_state.task_state = TaskStates.IDLE
        player_state.parameters_walk_to_entity = nil
        player_state.parameters_walking_direct = nil
        player_state.parameters_mine_entity = nil
        player_state.parameters_place_entity = nil
        player_state.parameters_move_items = nil
        player_state.parameters_craft_item = nil
        player_state.parameters_attack_nearest_enemy = nil
        player_state.parameters_research_technology = nil
        player_state.parameters_waiting = nil
		player_state.parameters_equip_armor = nil
        player_state.parameters_build_ghosts = nil
    end

    local function is_task_queue_empty(self)
        return #task_queue == 0
    end

    local function cancel_task(self)
        reset_task_state(nil)
    end

    local function cancel_all_tasks(self)
        reset_task_state(nil)
        __TS__ArraySetLength(task_queue, 0)
    end

    return {
        player_state = player_state,
        add_task = add_task,
        next_task = next_task,
        is_task_queue_empty = is_task_queue_empty,
        reset_task_state = reset_task_state,
        cancel_task = cancel_task,
        cancel_all_tasks = cancel_all_tasks
    }
end
return ____exports
 end,

["tools"] = function(...) 
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
local ____exports = {}
local ____inventory = require("utils.inventory")
local get_inventory_items = ____inventory.get_inventory_items

function ____exports.create_tools_remote_interface(self)
    remote.add_interface(
        "autorio_tools",
        {
            get_inventory_items = function(player_id)
                rcon.print(serpent.block(get_inventory_items(nil, player_id)))
                return true
            end,
            tag_selected_entity = function(label, category, player_id)
                local player = get_target_player(player_id)
                if not player or not player.character then
                    rcon.print('{"status":"error","message":"no_player"}')
                    return false
                end

                local ent = player.selected
                if not ent or not ent.valid then
                    rcon.print('{"status":"error","message":"nothing_selected"}')
                    return false
                end

                storage.monitored_nodes = storage.monitored_nodes or {}

                local linked_chest_unit = nil
                if ent.type == "reactor" then
                    local chests = ent.surface.find_entities_filtered{
                        position = ent.position,
                        radius = 6,
                        type = "logistic-container",
                        force = ent.force
                    }
                    if #chests > 0 and chests[1].valid then
                        linked_chest_unit = chests[1].unit_number
                    end
                end

                storage.monitored_nodes[label] = {
                    unit_number = ent.unit_number,
                    name = ent.name,
                    type = ent.type,
                    category = category or "critical",
                    linked_chest_unit = linked_chest_unit,
                    x = math.floor(ent.position.x),
                    y = math.floor(ent.position.y),
                    surface_name = ent.surface.name
                }

                local rep = {
                    status = "ok",
                    label = label,
                    entity = ent.name,
                    type = ent.type,
                    category = category or "critical",
                    has_linked_chest = (linked_chest_unit ~= nil)
                }
                rcon.print(helpers.table_to_json(rep))
                return true
            end,
            get_base_telemetry = function(player_id)
                local bot = get_companion_body()
                local player = get_target_player(player_id)
                local ref_entity = (bot and bot.valid) and bot or (player and player.character)
                if not ref_entity then
                    rcon.print('{"status":"error","message":"no_entity"}')
                    return false
                end

                local surface = ref_entity.surface
                local force = ref_entity.force
                local result = {
                    power = { status = "nominal", satisfaction = 1.0, output_kw = 0 },
                    fuel_alerts = {},
                    production_rates = {},
                    logistic_network = nil
                }

                local poles = surface.find_entities_filtered({
                    position = ref_entity.position,
                    radius = 40,
                    type = "electric-pole"
                })
                if #poles > 0 and poles[1].valid and poles[1].electric_network_statistics then
                    local net = poles[1].electric_network_statistics
                    local produced = 0
                    local consumed = 0
                    if net.output_counts then
                        for _, val in pairs(net.output_counts) do produced = produced + val end
                    end
                    if net.input_counts then
                        for _, val in pairs(net.input_counts) do consumed = consumed + val end
                    end
                    
                    local satisfaction = consumed > 0 and math.min(1.0, produced / consumed) or 1.0
                    result.power.satisfaction = math.floor(satisfaction * 100) / 100
                    result.power.output_kw = math.floor((produced * 60) / 1000)
                    result.power.status = satisfaction < 0.95 and "brownout_warning" or "nominal"
                end

                local boilers = surface.find_entities_filtered({
                    force = force,
                    name = "boiler"
                })
                for _, b in ipairs(boilers) do
                    if b.valid then
                        local fuel_inv = b.get_fuel_inventory()
                        local count = fuel_inv and fuel_inv.get_item_count() or 0
                        if count < 5 then
                            table.insert(result.fuel_alerts, {
                                unit = "boiler",
                                x = math.floor(b.position.x),
                                y = math.floor(b.position.y),
                                fuel_left = count
                            })
                        end
                    end
                end

                local success_stats, item_stats = pcall(function()
                    return force.get_item_production_statistics(surface)
                end)
                if success_stats and item_stats then
                    local tracked_items = {"iron-plate", "copper-plate", "stone-brick"}
                    for _, item_name in ipairs(tracked_items) do
                        local prod = 0
                        local cons = 0
                        pcall(function()
                            prod = item_stats.get_output_count(item_name)
                            cons = item_stats.get_input_count(item_name)
                        end)
                        if prod > 0 or cons > 0 then
                            result.production_rates[item_name] = {
                                produced = math.floor(prod),
                                consumed = math.floor(cons),
                                deficit = math.max(0, math.floor(cons - prod))
                            }
                        end
                    end
                end

                local log_net = surface.find_logistic_network_by_position(ref_entity.position, force.name)
                if not log_net and ref_entity.logistic_network then
                    log_net = ref_entity.logistic_network
                end

                if log_net and log_net.valid then
                    result.logistic_network = {
                        all_bots = log_net.all_logistic_robots,
                        available_bots = log_net.available_logistic_robots,
                        all_construction_bots = log_net.all_construction_robots,
                        available_construction_bots = log_net.available_construction_robots
                    }
                end
                
                result.named_nodes = {}
                storage.monitored_nodes = storage.monitored_nodes or {}

                for label, node in pairs(storage.monitored_nodes) do
                    local node_data = {
                        label = label,
                        type = node.type,
                        category = node.category,
                        valid = false
                    }

                    local ent = nil
                    if node.x and node.y and node.type then
                        local found = surface.find_entities_filtered{
                            position = {node.x, node.y},
                            radius = 2.0,
                            type = node.type
                        }
                        if #found > 0 and found[1].valid then
                            ent = found[1]
                        end
                    end

                    if ent and ent.valid then
                        node_data.valid = true

                        if node.type == "reactor" then
                            local finv = ent.get_fuel_inventory()
                            local queued_fuel = finv and finv.get_item_count("uranium-fuel-cell") or 0
                            local is_burning = (ent.burner and ent.burner.remaining_burning_fuel > 0) and 1 or 0
                            node_data.fuel_in_reactor = queued_fuel + is_burning
                            node_data.temperature = math.floor(ent.temperature or 0)
                            node_data.fuel_in_chest = 0

                            local chests = surface.find_entities_filtered{
                                position = ent.position,
                                radius = 6.0,
                                type = "logistic-container",
                                force = force
                            }
                            if #chests > 0 and chests[1].valid then
                                local cinv = chests[1].get_inventory(defines.inventory.chest)
                                if cinv then
                                    node_data.fuel_in_chest = cinv.get_item_count("uranium-fuel-cell")
                                end
                            end
                        elseif node.type == "storage-tank" or node.type == "pipe" then
                            node_data.fluids = ent.get_fluid_contents()
                        elseif node.type == "transport-belt" then
                            local line = ent.get_transport_line(1)
                            node_data.item_count_on_tile = line and line.get_item_count() or 0
                        elseif node.type == "container" or node.type == "logistic-container" then
                            local cinv = ent.get_inventory(defines.inventory.chest)
                            node_data.items = cinv and cinv.get_contents() or {}
                        end
                    end

                    result.named_nodes[label] = node_data
                end

                rcon.print(helpers.table_to_json(result))
                return true
            end,
            get_recipe = function(item_name, player_id)
                local bot = get_companion_body()
                local player = get_target_player(player_id)
                local force = bot and bot.force or (player and player.force)
                if not force then
                    rcon.print("{}")
                    return false
                end
                local recipe = force.recipes[item_name]
                if not recipe then
                    rcon.print("{}")
                    return false
                end
                if not recipe.enabled then
                    rcon.print("recipe locked")
                    return false
                end
                local ingredients = __TS__ArrayMap(
                    recipe.ingredients,
                    function(____, ingredient)
                        return {name = ingredient.name, count = ingredient.amount}
                    end
                )
                rcon.print(serpent.block(ingredients))
                return true
            end,
            scan_entities = function(radius, player_id)
                local bot = get_companion_body()
                if not bot or not bot.valid then
                    rcon.print('{"player":{"x":0,"y":0},"entities":[]}')
                    return false
                end
                radius = tonumber(radius) or 15
                local entities = bot.surface.find_entities_filtered({
                    position = bot.position,
                    radius = radius
                })

				-- Внутри scan_entities (control.lua)
				local human = get_target_player(1)
                local human_data = nil
                if human and human.character and human.character.valid then
                    human_data = {
                        name = human.name,
                        x = math.floor(human.position.x * 10) / 10,
                        y = math.floor(human.position.y * 10) / 10,
                        surface = human.surface.name
                    }
                end

                local result = {
                    player = {
                        x = math.floor(bot.position.x * 10) / 10,
                        y = math.floor(bot.position.y * 10) / 10
                    },
                    human_player = human_data,
                    entities = {},
                    telemetry = {
                        power_satisfaction = 1.0,
                        boilers_low_fuel = 0,
                        logistic_network = nil
                    }
                }

                local poles = bot.surface.find_entities_filtered({
                    position = bot.position,
                    radius = 40,
                    type = "electric-pole"
                })
                if #poles > 0 and poles[1].valid and poles[1].electric_network_statistics then
                    local net = poles[1].electric_network_statistics
                    local p_out = 0
                    local p_in = 0
                    if net.output_counts then
                        for _, val in pairs(net.output_counts) do p_out = p_out + val end
                    end
                    if net.input_counts then
                        for _, val in pairs(net.input_counts) do p_in = p_in + val end
                    end
                    if p_in > 0 then
                        result.telemetry.power_satisfaction = math.floor(math.min(1.0, p_out / p_in) * 100) / 100
                    end
                end

                local boilers = bot.surface.find_entities_filtered({
                    force = bot.force,
                    name = "boiler"
                })
                for _, b in ipairs(boilers) do
                    if b.valid then
                        local finv = b.get_fuel_inventory()
                        if finv and finv.get_item_count() < 5 then
                            result.telemetry.boilers_low_fuel = result.telemetry.boilers_low_fuel + 1
                        end
                    end
                end

                local log_net = bot.surface.find_logistic_network_by_position(bot.position, bot.force)
                if not log_net and bot.logistic_network then
                    log_net = bot.logistic_network
                end
                if log_net and log_net.valid then
                    result.telemetry.logistic_network = {
                        available_logistic_bots = log_net.available_logistic_robots,
                        all_logistic_bots = log_net.all_logistic_robots,
                        available_construction_bots = log_net.available_construction_robots,
                        all_construction_bots = log_net.all_construction_robots
                    }
                end

                local ore_added = {}
                local tree_count = 0
                local rock_count = 0
                
                for _, ent in ipairs(entities) do
                    if ent.valid and ent ~= bot then
                        if ent.type == "tree" then
                            tree_count = tree_count + 1
                            if tree_count <= 5 then
                                table.insert(result.entities, {
                                    id = ent.unit_number or 0,
                                    name = ent.name,
                                    type = "tree",
                                    x = math.floor(ent.position.x * 10) / 10,
                                    y = math.floor(ent.position.y * 10) / 10
                                })
                            end
                        elseif ent.type == "simple-entity" then
                            rock_count = rock_count + 1
                            if rock_count <= 3 then
                                table.insert(result.entities, {
                                    id = ent.unit_number or 0,
                                    name = ent.name,
                                    type = "rock",
                                    x = math.floor(ent.position.x * 10) / 10,
                                    y = math.floor(ent.position.y * 10) / 10
                                })
                            end
                        elseif ent.type == "resource" then
                            if not ore_added[ent.name] or ore_added[ent.name] < 2 then
                                ore_added[ent.name] = (ore_added[ent.name] or 0) + 1
                                table.insert(result.entities, {
                                    id = 0,
                                    name = ent.name,
                                    type = ent.type,
                                    x = math.floor(ent.position.x * 10) / 10,
                                    y = math.floor(ent.position.y * 10) / 10
                                })
                            end
                        else
                            local ent_data = {
                                id = ent.unit_number or 0,
                                name = ent.name,
                                type = ent.type,
                                x = math.floor(ent.position.x * 10) / 10,
                                y = math.floor(ent.position.y * 10) / 10
                            }

                            if ent.type == "container" or ent.type == "logistic-container" then
                                local c_inv = ent.get_inventory(defines.inventory.chest)
                                if c_inv and not c_inv.is_empty() then
                                    ent_data.items = {}
                                    local contents = c_inv.get_contents()
                                    for k, v in pairs(contents) do
                                        if type(v) == "table" and v.name then
                                            ent_data.items[v.name] = (ent_data.items[v.name] or 0) + (v.count or 1)
                                        elseif type(k) == "string" then
                                            ent_data.items[k] = v
                                        end
                                    end
                                end
                            end

                            table.insert(result.entities, ent_data)
                        end
                    end
                end
                rcon.print(helpers.table_to_json(result))
                return true
            end
        }
    )
end
return ____exports
 end,

["utils.math"] = function(...) 
local ____exports = {}
function ____exports.distance(self, a, b)
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2))
end
return ____exports
 end,

["control"] = function(...) 
local ____exports = {}
local ____task_manager = require("task_manager")
local new_task_manager = ____task_manager.new_task_manager
local ____tools = require("tools")
local create_tools_remote_interface = ____tools.create_tools_remote_interface
local ____types = require("types")
local TaskStates = ____types.TaskStates
local ____math = require("utils.math")
local distance = ____math.distance

create_tools_remote_interface(nil)
local setup_complete = false
local task_manager = new_task_manager(nil)

local function parse_direction(dir)
    if dir == nil then return defines.direction.north end

    if type(dir) == "string" then
        local s = string.lower(dir)
        if s == "north" or s == "up" or s == "север" or s == "вверх" or s == "n" then
            return defines.direction.north
        end
        if s == "east" or s == "right" or s == "восток" or s == "вправо" or s == "e" then
            return defines.direction.east
        end
        if s == "south" or s == "down" or s == "юг" or s == "вниз" or s == "s" then
            return defines.direction.south
        end
        if s == "west" or s == "left" or s == "запад" or s == "влево" or s == "w" then
            return defines.direction.west
        end
    end

    local n = tonumber(dir)
    if n then
        if n == 0 then return defines.direction.north end
        if n == 8 then return defines.direction.south end
        if n == 12 then return defines.direction.west end
        if n == 4 then return defines.direction.east end
        if n == 2 then return defines.direction.east end
        if n == 6 then return defines.direction.west end
    end

    return defines.direction.north
end

remote.add_interface(
    "autorio_operations",
    {
        walk_to = function(x, y)
            local target = {x = tonumber(x), y = tonumber(y)}
            task_manager:add_task({
                type = TaskStates.WALKING_DIRECT,
                target_position = target
            })
            log("[AUTORIO] Companion walk_to task: " .. serpent.line(target))
            return true
        end,
        walk_to_entity = function(entity_name, search_radius)
            log("[AUTORIO] Companion walk_to_entity task: " .. entity_name .. ", radius: " .. tostring(search_radius))
            task_manager:add_task({
                type = TaskStates.WALKING_TO_ENTITY,
                entity_name = entity_name,
                search_radius = search_radius,
                path = nil,
                path_drawn = false,
                path_index = 1,
                calculating_path = false,
                target_position = nil
            })
            return true
        end,
		walk_to_player = function()
            local human = get_target_player(1)
            if not human or not human.character or not human.character.valid then
                log("[AUTORIO] Cannot walk to player: human character not found")
                return false
            end

            local target = {
                x = math.floor(human.position.x * 10) / 10,
                y = math.floor(human.position.y * 10) / 10
            }

            task_manager:add_task({
                type = TaskStates.WALKING_DIRECT,
                target_position = target
            })
            log("[AUTORIO] Companion walk_to_player task queued to: " .. serpent.line(target))
            return true
        end,
        tagSelectedEntity = function(label, category)
            if type(label) == "table" then
                category = label.category
                label = label.label
            end

            local known_cats = { critical = true, production = true, temporary = true }
            if type(label) == "string" and known_cats[label] and category and not known_cats[category] then
                local temp = label
                label = category
                category = temp
            end

            local tools = remote.interfaces["autorio_tools"]
            if tools and tools["tag_selected_entity"] then
                return remote.call("autorio_tools", "tag_selected_entity", label or "Node", category or "critical", 1)
            end
            return false
        end,
        mine_entity = function(entity_name, count)
            if count == nil then count = 1 end
            task_manager:add_task({type = TaskStates.MINING, entity_name = entity_name, count = count})
            return true
        end,
        place_entity = function(entity_name, x, y, direction)
            local pos = nil
            if x ~= nil and y ~= nil then
                pos = {x = tonumber(x), y = tonumber(y)}
            end
            task_manager:add_task({
                type = TaskStates.PLACING,
                entity_name = entity_name,
                position = pos,
                direction = parse_direction(direction)
            })
            log("[AUTORIO] Companion place_entity task: " .. entity_name .. (pos and (" at " .. serpent.line(pos)) or ""))
            return true
        end,
        move_items = function(item_name, entity_name, max_count, to_entity, target_x, target_y)
            local target_pos = nil
            if target_x ~= nil and target_y ~= nil then
                target_pos = {x = tonumber(target_x), y = tonumber(target_y)}
            end
            task_manager:add_task({
                type = TaskStates.MOVING_ITEMS,
                item_name = item_name,
                entity_name = entity_name,
                max_count = max_count or math.huge,
                to_entity = to_entity,
                target_position = target_pos
            })
            return {true, "Task started"}
        end,
        build_ghosts = function(radius, max_count)
            task_manager:add_task({
                type = TaskStates.BUILDING_GHOSTS,
                radius = tonumber(radius) or 50,
                max_count = tonumber(max_count) or 200,
                built_count = 0,
                stuck_ticks = 0,
                last_pos = nil
            })
            log("[AUTORIO] Companion build_ghosts task started")
            return {true, "Ghost construction started"}
        end,
        wait = function(ticks)
            task_manager:add_task({type = TaskStates.WAITING, remaining_ticks = ticks})
            return {true, "Task started"}
        end,
        craft_item = function(item_name, count)
            if count == nil then count = 1 end
            local bot = get_companion_body()
            if not bot then return {false, "No companion"} end
            local recipe = bot.force.recipes[item_name]
            if not recipe then
                return {false, "Recipe not available"}
            end
            if not recipe.enabled then
                return {false, "Recipe not unlocked"}
            end
            task_manager:add_task({type = TaskStates.CRAFTING, item_name = item_name, count = count, crafted = 0})
            return {true, "Task started"}
        end,
		equip_armor = function(armor_name)
			local bot = get_companion_body()
			if not bot or not bot.valid then return false end

			task_manager:add_task({
				type = TaskStates.EQUIPPING_ARMOR,
				armor_name = armor_name or ""
			})
			log("[AUTORIO] Companion equip_armor queued: " .. tostring(armor_name))
			return true
		end,
        attack_nearest_enemy = function(search_radius)
            if search_radius == nil then search_radius = 50 end
            task_manager:add_task({type = TaskStates.ATTACKING, search_radius = search_radius, target = nil})
            return {true, "Task started"}
        end,
        research_technology = function(technology_name)
            local bot = get_companion_body()
            local force = bot and bot.force or (get_target_player(1) and get_target_player(1).force)
            if not force then return {false, "No force available"} end
            local tech = force.technologies[technology_name]
            if not tech then return {false, "Technology not found"} end
            if tech.researched then return {false, "Already researched"} end
            if not tech.enabled then return {false, "Not available"} end
            local research_added = force.add_research(tech)
            if research_added then return {true, "Research started"} end
            return {false, "Cannot start research"}
        end,
        deconstruct_area = function(radius)
            local rad = tonumber(radius) or 35
            local bot = get_companion_body()
            if not bot then return false end
            
            local entities = bot.surface.find_entities_filtered{
                position = bot.position,
                radius = rad,
                force = bot.force
            }
            for _, ent in ipairs(entities) do
                if ent.valid and ent ~= bot and ent.type ~= "entity-ghost" then
                    task_manager:add_task({
                        type = TaskStates.MINING,
                        entity_name = ent.name,
                        position = ent.position,
                        count = 1
                    })
                end
            end
            log("[AUTORIO] Companion deconstruct_area task queued")
            return true
        end,
        cancel_all_tasks = function()
            task_manager:cancel_all_tasks()
            return true
        end
    }
)

local function get_direction(self, start_position, end_position)
    local angle = math.atan2(end_position.y - start_position.y, start_position.x - end_position.x)
    local octant = (angle + math.pi) / (2 * math.pi) * 8 + 0.5
    if octant < 1 then return defines.direction.east end
    if octant < 2 then return defines.direction.northeast end
    if octant < 3 then return defines.direction.north end
    if octant < 4 then return defines.direction.northwest end
    if octant < 5 then return defines.direction.west end
    if octant < 6 then return defines.direction.southwest end
    if octant < 7 then return defines.direction.south end
    return defines.direction.southeast
end

local function get_nearest_entity(self, bot, entities)
    local min_distance = math.huge
    local nearest_entity = nil
    if #entities == 0 then return nil end
    for ____, entity in ipairs(entities) do
        local dist = (entity.position.x - bot.position.x) ^ 2 + (entity.position.y - bot.position.y) ^ 2
        if dist < min_distance then
            min_distance = dist
            nearest_entity = entity
        end
    end
    return nearest_entity
end

local function setup(self)
    local surface = game.surfaces[1]
    local enemies = surface.find_entities_filtered({force = "enemy"})
    for ____, enemy in ipairs(enemies) do
        enemy.destroy()
    end
    get_companion_body()
    setup_complete = true
    log("[AUTORIO] Setup complete with companion bot")
end

local function follow_path(self, bot, path)
    if #path == 0 then return true end
    local next_position = path[1].position
    local d = distance(nil, next_position, bot.position)
    if d < 0.1 then
        table.remove(path, 1)
        return false
    end
    local dir = get_direction(nil, bot.position, next_position)
    bot.walking_state = {walking = true, direction = dir}
    return false
end

local function state_walking_to_entity(self, bot)
    local params = task_manager.player_state.parameters_walk_to_entity
    if not params then return end
    if params.calculating_path then return end
    if params.path then
        if follow_path(nil, bot, params.path) then
            bot.walking_state = {walking = false}
            task_manager:reset_task_state()
            task_manager:next_task()
        end
        return
    end
    local filter = build_safe_entity_filter(
        params.entity_name, 
        bot.position, 
        params.search_radius, 
        bot.force
    )

    if not filter then
        log("[AUTORIO] [ERROR] Unknown entity: " .. tostring(params.entity_name))
        game.print("[AI Companion]: Unknown target entity '" .. tostring(params.entity_name) .. "'.")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local success, entities = pcall(function()
        return bot.surface.find_entities_filtered(filter)
    end)

    if not success or not entities or #entities == 0 then
        log("[AUTORIO] No entities found for " .. tostring(params.entity_name))
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    local nearest_entity = get_nearest_entity(nil, bot, entities)
    if nearest_entity and not params.calculating_path then
        local bbox = {{-0.5, -0.5}, {0.5, 0.5}}
        local start = bot.surface.find_non_colliding_position("iron-chest", bot.position, 10, 0.5, false)
        if not start then return end
        local collision_mask = {layers = {player = true, train = true, water_tile = true, object = true}, consider_tile_transitions = true}
        bot.surface.request_path({
            bounding_box = bbox,
            collision_mask = collision_mask,
            radius = 2,
            start = start,
            goal = nearest_entity.position,
            force = bot.force,
            entity_to_ignore = bot,
            pathfind_flags = {cache = false, no_break = true, prefer_straight_paths = false, allow_paths_through_own_entities = false}
        })
        params.calculating_path = true
        params.target_position = nearest_entity.position
    end
end

local function state_mining(self, bot)
    local params = task_manager.player_state.parameters_mine_entity
    if not params then return end

    -- Режим 1: Снос по координатам (deconstruct_area / демонтаж зданий)
    if params.position then
        local target_ents = bot.surface.find_entities_filtered({position = params.position, radius = 1.2, force = bot.force})
        local target_ent = nil
        for _, e in ipairs(target_ents) do
            if e.valid and e ~= bot and e.type ~= "entity-ghost" then
                target_ent = e
                break
            end
        end

        if not target_ent then
            bot.walking_state = {walking = false}
            task_manager:reset_task_state()
            task_manager:next_task()
            return
        end

        local dist_sq = (target_ent.position.x - bot.position.x)^2 + (target_ent.position.y - bot.position.y)^2
        -- Здания демонтируются на честной дистанции 8 клеток
        if dist_sq <= 64.0 then
            bot.walking_state = {walking = false}
            bot.mine_entity(target_ent, true)
            task_manager:reset_task_state()
            task_manager:next_task()
        else
            local dir = get_direction(nil, bot.position, target_ent.position)
            bot.walking_state = {walking = true, direction = dir}
        end
        return
    end

    -- Режим 2: Рубка деревьев, камней и добыча руды
    local target = params.current_target
    
    if target and target.valid then
        local dist_sq = (target.position.x - bot.position.x)^2 + (target.position.y - bot.position.y)^2
        local in_reach = bot.can_reach_entity(target) or (dist_sq <= 5.0)
        
        if in_reach then
            bot.walking_state = {walking = false}

            -- 1. Считаем сколько предметов было в рюкзаке бота до вызова
            local inv = bot.get_main_inventory()
            local total_before = inv and inv.get_item_count() or 0

            -- 2. Добываем
            local success = bot.mine_entity(target, true)

            -- 3. Считаем, сколько предметов добавилось (для руды всегда +1 за вызов)
            local total_after = inv and inv.get_item_count() or total_before
            local gained = total_after - total_before

            if gained > 0 then
                params.count = (params.count or 1) - gained
            else
                -- Если это дерево/камень и сущность просто разрушилась
                params.count = (params.count or 1) - 1
            end

            -- 4. Если набрали нужное количество (например, 100) — СТОП
            if (params.count or 0) <= 0 then
                params.current_target = nil
                bot.walking_state = {walking = false}
                task_manager:reset_task_state()
                task_manager:next_task()
                return
            end

            -- Если конкретный тайл руды или дерево всё же иссякли
            if not target.valid then
                params.current_target = nil
            end
        else
            local dir = get_direction(nil, bot.position, target.position)
            bot.walking_state = {walking = true, direction = dir}
        end
        return
    end

    params.current_target = nil

    local filter = build_safe_entity_filter(params.entity_name, bot.position, 35, bot.force)
    if not filter then
        bot.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local success, entities = pcall(function()
        return bot.surface.find_entities_filtered(filter)
    end)

    if not success or not entities or #entities == 0 then
        bot.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local nearest = get_nearest_entity(nil, bot, entities)
    if not nearest then
        bot.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    params.current_target = nearest
end

local function state_placing(self, bot)
    if not bot or not bot.valid then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Invalid companion"}
    end
    local params = task_manager.player_state.parameters_place_entity
    if not params then return end
    local surface = bot.surface
    local inventory = bot.get_main_inventory()
    if not inventory then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Cannot access companion inventory"}
    end
    local item_stack, _ = inventory.find_item_stack(params.entity_name)
    if not item_stack or item_stack.count == 0 then
        log("[AUTORIO] Entity not found in companion inventory: " .. params.entity_name)
        game.print("[AI Companion]: Cannot place '" .. params.entity_name .. "' (not in bot inventory).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    if not params.position then
        params.position = surface.find_non_colliding_position(params.entity_name, bot.position, 1, 1)
        if not params.position then
            task_manager:reset_task_state()
            task_manager:next_task()
            return {false, "Could not find a valid position"}
        end
    end

    if not surface.can_place_entity({name = params.entity_name, position = params.position, direction = params.direction, force = bot.force}) then
        log("[AUTORIO] Tile is occupied for " .. params.entity_name .. " at " .. serpent.line(params.position))
        game.print("[AI Companion]: Cannot place '" .. params.entity_name .. "' - tile occupied.")
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Tile is occupied"}
    end

    task_manager.player_state.task_state = TaskStates.IDLE
    local create_entity_args = {
        name = params.entity_name,
        position = params.position,
        direction = params.direction,
        force = bot.force,
        raise_built = true
    }
    local entity = surface.create_entity(create_entity_args)
    if entity then
        item_stack.count = item_stack.count - 1
        log("[AUTORIO] Entity placed successfully: " .. params.entity_name)
        task_manager:reset_task_state()
        task_manager:next_task()
        return {true, "Entity placed successfully", entity}
    end
    log("[AUTORIO] Failed to place entity: " .. params.entity_name)
    task_manager:reset_task_state()
    task_manager:next_task()
    return {false, "Failed to place entity"}
end

local function state_moving_items(self, bot)
    local parameters = task_manager.player_state.parameters_move_items
    if not parameters then return end

    -- Если переданы точные координаты целевого контейнера
    if parameters.target_position then
        local dist_sq = (parameters.target_position.x - bot.position.x)^2 + (parameters.target_position.y - bot.position.y)^2
        -- Если бот ещё не подошёл к ящику (дальше 2.5 клеток) — бежим к нему
        if dist_sq > 6.25 then
            local dir = get_direction(nil, bot.position, parameters.target_position)
            bot.walking_state = {walking = true, direction = dir}
            return
        else
            bot.walking_state = {walking = false}
        end
    end

    local filter_args = {position = bot.position, radius = 10, name = parameters.entity_name, force = bot.force}
    local nearby_entities = bot.surface.find_entities_filtered(filter_args)
    
    if parameters.target_position then
        local exact_entities = {}
        for _, ent in ipairs(nearby_entities) do
            if math.abs(ent.position.x - parameters.target_position.x) < 2.0 and math.abs(ent.position.y - parameters.target_position.y) < 2.0 then
                table.insert(exact_entities, ent)
            end
        end
        if #exact_entities > 0 then
            nearby_entities = exact_entities
        end
    end

    local bot_inventory = bot.get_main_inventory()
    if not bot_inventory or #nearby_entities == 0 then
        bot.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local moved_total = 0
    if parameters.to_entity then
        local item_stack, _ = bot_inventory.find_item_stack(parameters.item_name)
        if not item_stack then
            task_manager:reset_task_state()
            task_manager:next_task()
            return
        end
        for _, entity in ipairs(nearby_entities) do
            if moved_total >= parameters.max_count then break end
            local max_idx = entity.get_max_inventory_index()
            for i = 1, max_idx do
                local inv = entity.get_inventory(i)
                if inv and inv.can_insert({name = parameters.item_name}) then
                    local to_move = math.min(item_stack.count, parameters.max_count - moved_total)
                    if to_move > 0 then
                        local moved = inv.insert({name = parameters.item_name, count = to_move})
                        if moved > 0 then
                            bot_inventory.remove({name = parameters.item_name, count = moved})
                            moved_total = moved_total + moved
                        end
                    end
                end
                if moved_total >= parameters.max_count then break end
            end
        end
    else
        for _, entity in ipairs(nearby_entities) do
            if moved_total >= parameters.max_count then break end
            local max_idx = entity.get_max_inventory_index()
            for i = 1, max_idx do
                local inv = entity.get_inventory(i)
                if inv then
                    local removed = inv.remove({name = parameters.item_name, count = parameters.max_count - moved_total})
                    if removed > 0 then
                        local inserted = bot_inventory.insert({name = parameters.item_name, count = removed})
                        if inserted < removed then
                            inv.insert({name = parameters.item_name, count = removed - inserted})
                            moved_total = moved_total + inserted
                        else
                            moved_total = moved_total + removed
                        end
                    end
                end
                if moved_total >= parameters.max_count then break end
            end
        end
    end

    bot.walking_state = {walking = false}
    task_manager:reset_task_state()
    task_manager:next_task()
end

local function state_walking_direct(self, bot)
    local params = task_manager.player_state.parameters_walking_direct
    if not params or not params.target_position then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    local target = params.target_position
    local dir = get_direction(nil, bot.position, target)
    bot.walking_state = {walking = true, direction = dir}
    if (target.x - bot.position.x) ^ 2 + (target.y - bot.position.y) ^ 2 < 1.0 then
        bot.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end

local function state_building_ghosts(self, bot)
    local params = task_manager.player_state.parameters_build_ghosts
    if not params then return end

    if params.built_count >= params.max_count then
        bot.walking_state = {walking = false}
        game.print("[AI Companion]: Finished blueprint construction limit (" .. tostring(params.built_count) .. " entities).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local ghosts = bot.surface.find_entities_filtered({
        position = bot.position,
        radius = params.radius,
        type = "entity-ghost"
    })

    if #ghosts == 0 then
        bot.walking_state = {walking = false}
        game.print("[AI Companion]: No ghosts left in radius " .. tostring(params.radius) .. ".")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local inv = bot.get_main_inventory()
    if not inv then return end

    local best_ghost = nil
    local best_dist = math.huge
    local missing_item_name = nil

    for _, ghost in ipairs(ghosts) do
        if ghost.valid then
            local item_name = ghost.ghost_name
            local item_count = inv.get_item_count(item_name)
            local d = (ghost.position.x - bot.position.x)^2 + (ghost.position.y - bot.position.y)^2
            
            if item_count > 0 then
                if d < best_dist then
                    best_dist = d
                    best_ghost = ghost
                end
            elseif not missing_item_name then
                missing_item_name = item_name
            end
        end
    end

    if not best_ghost then
        bot.walking_state = {walking = false}
        
        if bot.crafting_queue_size and bot.crafting_queue_size > 0 then
            return
        end

        if missing_item_name then
            local crafted = bot.begin_crafting({recipe = missing_item_name, count = 1})
            if crafted > 0 then
                return
            else
                game.print("[AI Companion]: Missing materials to craft '" .. tostring(missing_item_name) .. "'.")
                task_manager:reset_task_state()
                task_manager:next_task()
                return
            end
        else
            task_manager:reset_task_state()
            task_manager:next_task()
            return
        end
    end

    if math.abs(bot.position.x - best_ghost.position.x) < 0.85 and math.abs(bot.position.y - best_ghost.position.y) < 0.85 then
        bot.walking_state = {walking = true, direction = defines.direction.south}
        return
    end

    local d_tiles = math.sqrt(best_dist)
    local dir = get_direction(nil, bot.position, best_ghost.position)

    if d_tiles > 6.0 then
        bot.walking_state = {walking = true, direction = dir}

        if params.last_pos and math.abs(params.last_pos.x - bot.position.x) < 0.05 and math.abs(params.last_pos.y - bot.position.y) < 0.05 then
            params.stuck_ticks = (params.stuck_ticks or 0) + 1
            if params.stuck_ticks > 30 then
                local escape_dir = (dir + 4) % 16
                bot.walking_state = {walking = true, direction = escape_dir}
                params.stuck_ticks = 0
            end
        else
            params.stuck_ticks = 0
        end
        params.last_pos = {x = bot.position.x, y = bot.position.y}
        return
    end

    if d_tiles > 2.5 then
        bot.walking_state = {walking = true, direction = dir}
    else
        bot.walking_state = {walking = false}
    end

    local item_stack = inv.find_item_stack(best_ghost.ghost_name)
    if item_stack and item_stack.count > 0 then
        item_stack.count = item_stack.count - 1
        local collided, created = best_ghost.revive({return_item = false, raise_revive = true})
        if created then
            params.built_count = params.built_count + 1
        else
            inv.insert({name = best_ghost.ghost_name, count = 1})
        end
    end
end

local function state_equipping_armor(self, bot)
    local params = task_manager.player_state.parameters_equip_armor
    if not params then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local minv = bot.get_main_inventory()
    local ainv = bot.get_inventory(defines.inventory.character_armor)
    if not minv or not ainv then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local target_name = params.armor_name
    if not target_name or target_name == "" then
        for i = 1, #minv do
            local s = minv[i]
            if s and s.valid_for_read and prototypes.item[s.name] and prototypes.item[s.name].type == "armor" then
                target_name = s.name
                break
            end
        end
    end

    if not target_name or minv.get_item_count(target_name) == 0 then
        log("[AUTORIO] Armor not in inventory yet during equip state")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    if not ainv.is_empty() then
        local cur = ainv[1]
        if cur and cur.valid_for_read then
            minv.insert({name = cur.name, count = 1})
            ainv.clear()
        end
    end

    local removed = minv.remove({name = target_name, count = 1})
    ainv.insert({name = target_name, count = removed})
    game.print("[AI Companion]: Successfully equipped " .. tostring(target_name) .. "!")

    task_manager:reset_task_state()
    task_manager:next_task()
end

local function state_crafting(self, bot)
    local params = task_manager.player_state.parameters_craft_item
    if not params then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    -- Если крафт ещё не стартовал
    if not params.started then
        local recipe_name = params.item_name or params.recipe_name or "stone-furnace"
        local count = tonumber(params.count) or 1
        
        local queued = bot.begin_crafting{recipe = recipe_name, count = count}
        if queued == 0 then
            log("[AUTORIO] Cannot craft " .. tostring(recipe_name) .. ", not enough items")
            task_manager:reset_task_state()
            task_manager:next_task()
            return
        end
        params.started = true
        params.wait_ticks = 10 -- Даем 10 тиков движку на прогрев очереди
        return
    end

    if params.wait_ticks and params.wait_ticks > 0 then
        params.wait_ticks = params.wait_ticks - 1
        return
    end

    -- Когда очередь опустела — крафт закончен
    if bot.crafting_queue_size == 0 then
        log("[AUTORIO] Crafting completed")
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end

local function state_researching(self, bot)
    local params = task_manager.player_state.parameters_research_technology
    if not params then return end
    local force = bot.force
    local tech = force.technologies[params.technology_name]
    if tech and (tech.researched or force.current_research ~= tech) then
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end

local function state_waiting(self)
    local params = task_manager.player_state.parameters_waiting
    if not params or params.remaining_ticks <= 0 then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    params.remaining_ticks = params.remaining_ticks - 1
end

script.on_event(defines.events.on_tick, function(unused_event)
    if not setup_complete then setup(nil) end
    local bot = get_companion_body()
    if bot == nil or not bot.valid then return end
    
    local state = task_manager.player_state.task_state
    if state == TaskStates.IDLE then return end
    if state == TaskStates.WALKING_TO_ENTITY then state_walking_to_entity(nil, bot)
    elseif state == TaskStates.MINING then state_mining(nil, bot)
    elseif state == TaskStates.PLACING then state_placing(nil, bot)
    elseif state == TaskStates.MOVING_ITEMS then state_moving_items(nil, bot)
    elseif state == TaskStates.BUILDING_GHOSTS then state_building_ghosts(nil, bot)
    elseif state == TaskStates.RESEARCHING then state_researching(nil, bot)
    elseif state == TaskStates.WALKING_DIRECT then state_walking_direct(nil, bot)
    elseif state == TaskStates.WAITING then state_waiting(nil)
	elseif state == TaskStates.EQUIPPING_ARMOR then state_equipping_armor(nil, bot)
    elseif state == TaskStates.CRAFTING then state_crafting(nil, bot)
    end
end)

log("[AUTORIO] Mod loaded (Autonomous Companion Architecture v4)")
return ____exports
 end,
["utils.hot_reload"] = function(...) return {} end,
["hot_reload"] = function(...) return {} end,
}
return require("control", ...)