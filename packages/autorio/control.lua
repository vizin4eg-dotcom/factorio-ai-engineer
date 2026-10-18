--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua (Enhanced for Coordinates, Ghost Building & Scanning) ]]

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

    -- 3. Safe type verification using pcall to prevent crashes on invalid types
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
    log("[AUTORIO] Getting inventory items for player: " .. tostring(player_id))
    local player = get_target_player(player_id)
    if not player then return {} end
    local main_inventory = player.get_main_inventory()
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
            game.print("[AUTORIO] All operations completed")
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
            elseif switch_state == TaskStates.CRAFTING then
                do
                    local player = get_target_player(1)
                    if not player then
                        log("[AUTORIO] No player found for crafting")
                        return
                    end
                    local queued_count = player.begin_crafting({count = task.count, recipe = task.item_name})
                    if queued_count == 0 then
                        log("[AUTORIO] Cannot craft " .. tostring(task.item_name) .. ": not enough raw materials")
                        game.print("[AI Agent]: Not enough raw materials to craft " .. tostring(task.item_name))
                        player_state.task_state = TaskStates.IDLE
                        next_task(nil)
                        break
                    end
                    task.count = queued_count
                    player_state.parameters_craft_item = task
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
        local player = get_target_player(1)
        if player then
            player.walking_state = {walking = false}
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
                local player = get_target_player(player_id)
                if not player then
                    rcon.print("{}")
                    return false
                end
                rcon.print(serpent.block(get_inventory_items(nil, player.index)))
                return true
            end,
			get_base_telemetry = function(player_id)
                local player = get_target_player(player_id)
                if not player or not player.character then
                    rcon.print('{"status":"error","message":"no_player"}')
                    return false
                end

                local surface = player.surface
                local force = player.force
                local result = {
                    power = { status = "nominal", satisfaction = 1.0, output_kw = 0 },
                    fuel_alerts = {},
                    production_rates = {},
                    logistic_network = nil
                }

                -- 1. Энергетика: ищем ближайший столб ЛЭП в радиусе 40 тайлов
                local poles = surface.find_entities_filtered({
                    position = player.position,
                    radius = 40,
                    type = "electric-pole"
                })
                if #poles > 0 and poles[1].valid and poles[1].electric_network_statistics then
                    local net = poles[1].electric_network_statistics
                    local produced = net.get_flow_count({name = "electric-energy-produced", input = false, precision_index = defines.flow_precision_index.five_seconds})
                    local consumed = net.get_flow_count({name = "electric-energy-consumed", input = true, precision_index = defines.flow_precision_index.five_seconds})
                    
                    local satisfaction = consumed > 0 and math.min(1.0, produced / consumed) or 1.0
                    result.power.satisfaction = math.floor(satisfaction * 100) / 100
                    result.power.output_kw = math.floor((produced * 60) / 1000)
                    result.power.status = satisfaction < 0.95 and "brownout_warning" or "nominal"
                end

                -- 2. Критическое топливо: проверка бойлеров на карте
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

                -- 3. Баланс ключевых ресурсов (плиты за последнюю 1 минуту)
                local item_stats = force.get_item_production_statistics(surface)
                local tracked_items = {"iron-plate", "copper-plate", "stone-brick"}
                for _, item_name in ipairs(tracked_items) do
                    local prod = item_stats.get_flow_count({name = item_name, input = false, precision_index = defines.flow_precision_index.one_minute})
                    local cons = item_stats.get_flow_count({name = item_name, input = true, precision_index = defines.flow_precision_index.one_minute})
                    if prod > 0 or cons > 0 then
                        result.production_rates[item_name] = {
                            produced_per_min = prod,
                            consumed_per_min = cons,
                            deficit = math.max(0, cons - prod)
                        }
                    end
                end

                -- 4. Логистическая сеть (активируется автоматически, когда есть робопорты)
                local log_net = surface.find_logistic_network_by_position(player.position, force)
                if log_net and log_net.valid then
                    result.logistic_network = {
                        all_bots = log_net.all_logistic_robots,
                        available_bots = log_net.available_logistic_robots,
                        all_construction_bots = log_net.all_construction_robots,
                        available_construction_bots = log_net.available_construction_bots
                    }
                end

                rcon.print(helpers.table_to_json(result))
                return true
            end,
            get_recipe = function(item_name, player_id)
                local player = get_target_player(player_id)
                if not player then
                    rcon.print("{}")
                    return false
                end
                local recipe = player.force.recipes[item_name]
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
                local player = get_target_player(player_id)
                if not player or not player.character then
                    rcon.print('{"player":{"x":0,"y":0},"entities":[]}')
                    return false
                end
                radius = tonumber(radius) or 15
                local entities = player.surface.find_entities_filtered({
                    position = player.position,
                    radius = radius
                })
                local result = {
                    player = {
                        x = math.floor(player.position.x * 10) / 10,
                        y = math.floor(player.position.y * 10) / 10
                    },
                    entities = {},
                    telemetry = {
                        power_satisfaction = 1.0,
                        boilers_low_fuel = 0,
                        logistic_network = nil
                    }
                }

                -- 1. Base telemetry: Power grid
                local poles = player.surface.find_entities_filtered({
                    position = player.position,
                    radius = 40,
                    type = "electric-pole"
                })
                if #poles > 0 and poles[1].valid and poles[1].electric_network_statistics then
                    local net = poles[1].electric_network_statistics
                    local p_out = net.get_flow_count({name = "electric-energy-produced", input = false, precision_index = defines.flow_precision_index.five_seconds})
                    local p_in = net.get_flow_count({name = "electric-energy-consumed", input = true, precision_index = defines.flow_precision_index.five_seconds})
                    if p_in > 0 then
                        result.telemetry.power_satisfaction = math.floor(math.min(1.0, p_out / p_in) * 100) / 100
                    end
                end

                -- 2. Base telemetry: Low fuel boilers (< 5 items)
                local boilers = player.surface.find_entities_filtered({
                    force = player.force,
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

                -- 3. Base telemetry: Logistic network overview (if active)
                local log_net = player.surface.find_logistic_network_by_position(player.position, player.force)
                if log_net and log_net.valid then
                    result.telemetry.logistic_network = {
                        available_logistic_bots = log_net.available_logistic_robots,
                        all_logistic_bots = log_net.all_logistic_robots,
                        available_construction_bots = log_net.available_construction_robots,
                        all_construction_bots = log_net.all_construction_robots
                    }
                end

                local ore_added = {}
                
                for _, ent in ipairs(entities) do
                    if ent.valid and ent ~= player.character then
                        if ent.type ~= "tree" then
                            if ent.type == "resource" then
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

                                -- Inspect chest contents if entity is a container
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

remote.add_interface(
    "autorio_operations",
    {
        walk_to = function(x, y)
            local target = {x = tonumber(x), y = tonumber(y)}
            task_manager:add_task({
                type = TaskStates.WALKING_DIRECT,
                target_position = target
            })
            log("[AUTORIO] New walk_to task: " .. serpent.line(target))
            return true
        end,
        walk_to_entity = function(entity_name, search_radius)
            log("[AUTORIO] New walk_to_entity task: " .. entity_name .. ", radius: " .. tostring(search_radius))
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
                direction = direction and tonumber(direction) or nil
            })
            log("[AUTORIO] New place_entity task: " .. entity_name .. (pos and (" at " .. serpent.line(pos)) or ""))
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
            log("[AUTORIO] New build_ghosts task started")
            return {true, "Ghost construction started"}
        end,
        wait = function(ticks)
            task_manager:add_task({type = TaskStates.WAITING, remaining_ticks = ticks})
            return {true, "Task started"}
        end,
        craft_item = function(item_name, count)
            if count == nil then count = 1 end
            local player = get_target_player(1)
            if not player then return {false, "No player"} end
            local recipe = player.force.recipes[item_name]
            if not recipe then
                return {false, "Recipe not available"}
            end
            if not recipe.enabled then
                return {false, "Recipe not unlocked"}
            end
            task_manager:add_task({type = TaskStates.CRAFTING, item_name = item_name, count = count, crafted = 0})
            return {true, "Task started"}
        end,
        attack_nearest_enemy = function(search_radius)
            if search_radius == nil then search_radius = 50 end
            task_manager:add_task({type = TaskStates.ATTACKING, search_radius = search_radius, target = nil})
            return {true, "Task started"}
        end,
        research_technology = function(technology_name)
            local player = get_target_player(1)
            if not player then return {false, "No player"} end
            local force = player.force
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
            local player = get_target_player(1)
            if not player then return false end
            
            local entities = player.surface.find_entities_filtered{
                position = player.position,
                radius = rad,
                force = player.force
            }
            for _, ent in ipairs(entities) do
                if ent.valid and ent ~= player.character and ent.type ~= "entity-ghost" then
                    task_manager:add_task({
                        type = TaskStates.MINING,
                        entity_name = ent.name,
                        position = ent.position,
                        count = 1
                    })
                end
            end
            log("[AUTORIO] New deconstruct_area task queued")
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

local function get_nearest_entity(self, player, entities)
    local min_distance = math.huge
    local nearest_entity = nil
    if #entities == 0 then return nil end
    for ____, entity in ipairs(entities) do
        local dist = (entity.position.x - player.position.x) ^ 2 + (entity.position.y - player.position.y) ^ 2
        if dist < min_distance then
            min_distance = dist
            nearest_entity = entity
        end
    end
    return nearest_entity
end

local function start_mining(self, player, entity_position)
    player.update_selected_entity(entity_position)
    player.mining_state = {mining = true, position = entity_position}
end

script.on_event(defines.events.on_script_path_request_finished, function(event)
    if task_manager.player_state.task_state ~= TaskStates.WALKING_TO_ENTITY then return end
    if not task_manager.player_state.parameters_walk_to_entity then return end
    if not event.path then
        task_manager.player_state.task_state = TaskStates.WALKING_DIRECT
        task_manager.player_state.parameters_walking_direct = {
            type = TaskStates.WALKING_DIRECT,
            target_position = task_manager.player_state.parameters_walk_to_entity.target_position
        }
        task_manager.player_state.parameters_walk_to_entity = nil
        return
    end
    task_manager.player_state.parameters_walk_to_entity.path = event.path
    task_manager.player_state.parameters_walk_to_entity.path_drawn = false
    task_manager.player_state.parameters_walk_to_entity.path_index = 1
    task_manager.player_state.parameters_walk_to_entity.calculating_path = false
end)

script.on_event(defines.events.on_player_mined_entity, function(unused_event)
    if task_manager.player_state.task_state ~= TaskStates.MINING then return end
    if not task_manager.player_state.parameters_mine_entity then return end
    if task_manager.player_state.parameters_mine_entity.count <= 0 then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    task_manager.player_state.parameters_mine_entity.count = task_manager.player_state.parameters_mine_entity.count - 1
end)

local function setup(self)
    local surface = game.surfaces[1]
    local enemies = surface.find_entities_filtered({force = "enemy"})
    for ____, enemy in ipairs(enemies) do
        enemy.destroy()
    end
    setup_complete = true
    log("[AUTORIO] Setup complete")
end

local function follow_path(self, player, path)
    if #path == 0 then return true end
    local next_position = path[1].position
    local d = distance(nil, next_position, player.position)
    if d < 0.1 then
        table.remove(path, 1)
        return false
    end
    local dir = get_direction(nil, player.position, next_position)
    player.walking_state = {walking = true, direction = dir}
    return false
end

local function state_walking_to_entity(self, player)
    local params = task_manager.player_state.parameters_walk_to_entity
    if not params then return end
    if params.calculating_path then return end
    if params.path then
        if follow_path(nil, player, params.path) then
            player.walking_state = {walking = false}
            task_manager:reset_task_state()
            task_manager:next_task()
        end
        return
    end
    local filter = build_safe_entity_filter(
        params.entity_name, 
        player.position, 
        params.search_radius, 
        player.force
    )

    if not filter then
        log("[AUTORIO] [ERROR] Unknown entity or category: " .. tostring(params.entity_name))
        game.print("[AI Agent]: I cannot find target '" .. tostring(params.entity_name) .. "' (unknown entity).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local success, entities = pcall(function()
        return player.surface.find_entities_filtered(filter)
    end)

    if not success or not entities or #entities == 0 then
        log("[AUTORIO] No entities found for " .. tostring(params.entity_name))
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    local nearest_entity = get_nearest_entity(nil, player, entities)
    if nearest_entity and not params.calculating_path then
        local character = player.character
        if not character then return end
        local bbox = {{-0.5, -0.5}, {0.5, 0.5}}
        local start = player.surface.find_non_colliding_position("iron-chest", character.position, 10, 0.5, false)
        if not start then return end
        local collision_mask = {layers = {player = true, train = true, water_tile = true, object = true}, consider_tile_transitions = true}
        player.surface.request_path({
            bounding_box = bbox,
            collision_mask = collision_mask,
            radius = 2,
            start = start,
            goal = nearest_entity.position,
            force = player.force,
            entity_to_ignore = character,
            pathfind_flags = {cache = false, no_break = true, prefer_straight_paths = false, allow_paths_through_own_entities = false}
        })
        params.calculating_path = true
        params.target_position = nearest_entity.position
    end
end

local function state_mining(self, player)
    local params = task_manager.player_state.parameters_mine_entity
    if not params then return end

    if params.position then
        local target_ents = player.surface.find_entities_filtered({position = params.position, radius = 0.8, force = player.force})
        local has_target = false
        for _, e in ipairs(target_ents) do
            if e.valid and e ~= player.character then
                has_target = true
                break
            end
        end
        if not has_target then
            -- Entity already mined / gone
            player.walking_state = {walking = false}
            task_manager:reset_task_state()
            task_manager:next_task()
            return
        end

        local d = (params.position.x - player.position.x)^2 + (params.position.y - player.position.y)^2
        if d > 9.0 then
            local dir = get_direction(nil, player.position, params.position)
            player.walking_state = {walking = true, direction = dir}
            return
        else
            player.walking_state = {walking = false}
            if not player.mining_state.mining then
                start_mining(nil, player, params.position)
            end
            return
        end
    end

    local filter = build_safe_entity_filter(
        params.entity_name, 
        player.position, 
        15, 
        player.force
    )

    if not filter then
        player.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local success, entities = pcall(function()
        return player.surface.find_entities_filtered(filter)
    end)

    if not success or not entities or #entities == 0 then
        player.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local nearest = get_nearest_entity(nil, player, entities)
    if not nearest then
        player.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    if not player.can_reach_entity(nearest) then
        local dir = get_direction(nil, player.position, nearest.position)
        player.walking_state = {walking = true, direction = dir}
    else
        player.walking_state = {walking = false}
        if not player.mining_state.mining then
            start_mining(nil, player, nearest.position)
        end
    end
end

local function state_placing(self, player)
    if not player then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Invalid player"}
    end
    local params = task_manager.player_state.parameters_place_entity
    if not params then return end
    local surface = player.surface
    local inventory = player.get_main_inventory()
    if not inventory then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Cannot access player inventory"}
    end
    local item_stack, _ = inventory.find_item_stack(params.entity_name)
    if not item_stack or item_stack.count == 0 then
        log("[AUTORIO] Entity not found in inventory: " .. params.entity_name)
        game.print("[AI Agent]: Cannot place '" .. params.entity_name .. "' (not in inventory).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    if not params.position then
        params.position = surface.find_non_colliding_position(params.entity_name, player.position, 1, 1)
        if not params.position then
            task_manager:reset_task_state()
            task_manager:next_task()
            return {false, "Could not find a valid position"}
        end
    end

    -- Prevent ghost overlapping / double placements on occupied tiles
    if not surface.can_place_entity({name = params.entity_name, position = params.position, direction = params.direction, force = player.force}) then
        log("[AUTORIO] Tile is already occupied for " .. params.entity_name .. " at " .. serpent.line(params.position))
        game.print("[AI Agent]: Cannot place '" .. params.entity_name .. "' - tile is occupied.")
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Tile is occupied"}
    end

    task_manager.player_state.task_state = TaskStates.IDLE
    local create_entity_args = {
        name = params.entity_name,
        position = params.position,
        direction = params.direction,
        force = player.force,
        raise_built = true,
        player = player
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

local function state_moving_items(self, player)
    local parameters = task_manager.player_state.parameters_move_items
    if not parameters then return end
    
    local filter_args = {position = player.position, radius = 10, name = parameters.entity_name, force = player.force}
    local nearby_entities = player.surface.find_entities_filtered(filter_args)
    
    -- Tolerance expanded to 1.5 tiles to cover centers of 2x2 and 3x3 structures
    if parameters.target_position then
        local exact_entities = {}
        for _, ent in ipairs(nearby_entities) do
            if math.abs(ent.position.x - parameters.target_position.x) < 1.5 and math.abs(ent.position.y - parameters.target_position.y) < 1.5 then
                table.insert(exact_entities, ent)
            end
        end
        if #exact_entities > 0 then
            nearby_entities = exact_entities
        end
    end

    local player_inventory = player.get_main_inventory()
    if not player_inventory then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    local moved_total = 0
    if parameters.to_entity then
        local item_stack, _ = player_inventory.find_item_stack(parameters.item_name)
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
                            player_inventory.remove({name = parameters.item_name, count = moved})
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
                        local inserted = player_inventory.insert({name = parameters.item_name, count = removed})
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
    task_manager:reset_task_state()
    task_manager:next_task()
end

local function state_walking_direct(self, player)
    local params = task_manager.player_state.parameters_walking_direct
    if not params or not params.target_position then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
    local target = params.target_position
    local dir = get_direction(nil, player.position, target)
    player.walking_state = {walking = true, direction = dir}
    if (target.x - player.position.x) ^ 2 + (target.y - player.position.y) ^ 2 < 1.0 then
        player.walking_state = {walking = false}
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end

-- Autonomous Ghost Construction ("Live Drone") Engine
local function state_building_ghosts(self, player)
    local params = task_manager.player_state.parameters_build_ghosts
    if not params then return end

    if params.built_count >= params.max_count then
        player.walking_state = {walking = false}
        game.print("[AI Agent]: Finished blueprint construction limit (" .. tostring(params.built_count) .. " entities).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local ghosts = player.surface.find_entities_filtered({
        position = player.position,
        radius = params.radius,
        type = "entity-ghost"
    })

    if #ghosts == 0 then
        player.walking_state = {walking = false}
        game.print("[AI Agent]: No ghosts left to construct in radius " .. tostring(params.radius) .. ".")
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local inv = player.get_main_inventory()
    if not inv then return end

    -- 1. Find the closest ghost for which we already have items in inventory
    local best_ghost = nil
    local best_dist = math.huge
    local missing_item_name = nil

    for _, ghost in ipairs(ghosts) do
        if ghost.valid then
            local item_name = ghost.ghost_name
            local item_count = inv.get_item_count(item_name)
            local d = (ghost.position.x - player.position.x)^2 + (ghost.position.y - player.position.y)^2
            
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

    -- 2. If no ready item, manage crafting safely
    if not best_ghost then
        player.walking_state = {walking = false}
        
        -- If player is currently crafting, just wait for the item to complete!
        if player.crafting_queue_size and player.crafting_queue_size > 0 then
            return
        end

        -- If not crafting, try to queue ONLY 1 item of the missing recipe
        if missing_item_name then
            local crafted = player.begin_crafting({recipe = missing_item_name, count = 1})
            if crafted > 0 then
                return -- Craft started, will build once ready
            else
                -- Truly out of raw materials for this ghost, try to find another ghost recipe or exit
                game.print("[AI Agent]: Missing materials to craft '" .. tostring(missing_item_name) .. "'.")
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

    -- 3. Movement and reach logic (maintain safe 4-6 tiles reach distance)
    local d_tiles = math.sqrt(best_dist)
    if d_tiles > 5.0 then
        local dir = get_direction(nil, player.position, best_ghost.position)
        player.walking_state = {walking = true, direction = dir}

        -- Stuck Watchdog ONLY applies when actively trying to walk
        if params.last_pos and math.abs(params.last_pos.x - player.position.x) < 0.05 and math.abs(params.last_pos.y - player.position.y) < 0.05 then
            params.stuck_ticks = (params.stuck_ticks or 0) + 1
            if params.stuck_ticks > 30 then
                -- Jiggle movement perpendicular to break free from corners
                local escape_dir = (dir + 4) % 16
                player.walking_state = {walking = true, direction = escape_dir}
                params.stuck_ticks = 0
            end
        else
            params.stuck_ticks = 0
        end
        params.last_pos = {x = player.position.x, y = player.position.y}
        return
    end

    -- 4. Target in reach: stop and construct
    player.walking_state = {walking = false}

    -- Safety check: avoid building directly underneath player feet
    if math.abs(player.position.x - best_ghost.position.x) < 0.8 and math.abs(player.position.y - best_ghost.position.y) < 0.8 then
        local escape_dir = defines.direction.south
        player.walking_state = {walking = true, direction = escape_dir}
        return
    end

    -- Revive ghost and consume 1 item
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

local function state_researching(self, player)
    local params = task_manager.player_state.parameters_research_technology
    if not params then return end
    local force = player.force
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
    local player = get_target_player(1)
    if player == nil or player.character == nil then return end
    local state = task_manager.player_state.task_state
    if state == TaskStates.IDLE then return end
    if state == TaskStates.WALKING_TO_ENTITY then state_walking_to_entity(nil, player)
    elseif state == TaskStates.MINING then state_mining(nil, player)
    elseif state == TaskStates.PLACING then state_placing(nil, player)
    elseif state == TaskStates.MOVING_ITEMS then state_moving_items(nil, player)
    elseif state == TaskStates.BUILDING_GHOSTS then state_building_ghosts(nil, player)
    elseif state == TaskStates.RESEARCHING then state_researching(nil, player)
    elseif state == TaskStates.WALKING_DIRECT then state_walking_direct(nil, player)
    elseif state == TaskStates.WAITING then state_waiting(nil)
    end
end)

script.on_event(defines.events.on_player_crafted_item, function(event)
    local params = task_manager.player_state.parameters_craft_item
    if not params or task_manager.player_state.task_state ~= TaskStates.CRAFTING then return end
    if event.recipe and event.recipe.name ~= params.item_name then return end
    params.crafted = (params.crafted or 0) + 1
    if params.crafted >= params.count then
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end)

log("[AUTORIO] Mod loaded (Enhanced Coordinates & Ghost Builder v3)")
return ____exports
 end,
["utils.hot_reload"] = function(...) return {} end,
["hot_reload"] = function(...) return {} end,
}
return require("control", ...)