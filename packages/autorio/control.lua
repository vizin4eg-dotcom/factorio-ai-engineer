--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua (Enhanced for Coordinates & Scanning) ]]

local ____modules = {}
local ____moduleCache = {}
local ____originalRequire = require
local function build_safe_entity_filter(target_name, center_pos, radius, force)
    local filter = {
        position = center_pos,
        radius = radius
    }
    
    if not target_name or target_name == "" then
        return nil
    end

    target_name = string.lower(target_name)

    -- 1. Словарь популярных категорий и синонимов
    if target_name == "tree" or target_name == "trees" or target_name == "wood" then
        filter.type = "tree"
        return filter
    end

    if target_name == "rock" or target_name == "rocks" or target_name == "boulder" or target_name == "stone-rock" then
        -- В Factorio камни — это simple-entity со словом rock в имени
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

    -- 2. Проверка точного имени прототипа в базе Factorio
    if prototypes.entity[target_name] then
        filter.name = target_name
        return filter
    end

    -- 3. Безопасная проверка: вдруг передали имя типа (furnace, container, car, wall и т.д.)
    -- Если передать невалидный type, find_entities_filtered тоже может ругнуться, 
    -- поэтому проверяем через защищенный вызов
    local test_filter = {position = center_pos, radius = radius, type = target_name}
    local success, _ = pcall(function()
        game.surfaces[1].find_entities_filtered(test_filter)
    end)
    if success then
        return test_filter
    end

    -- Если ничего не подошло — возвращаем nil, чтобы не ронять сервер
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
        function(____, ____bindingPattern0)
            local count
            local name
            name = ____bindingPattern0.name
            count = ____bindingPattern0.count
            return {name = name, count = count}
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
            log("[AUTORIO] Task state is not IDLE, wont execute next task")
            return
        end
        local task = table.remove(task_queue, 1)
        if not task then
            player_state.task_state = TaskStates.IDLE
            game.print("[AUTORIO] All operations completed")
            log("[AUTORIO] All operations completed")
            return
        end
        log((("[AUTORIO] Next task: " .. task.type) .. ", task queue length: ") .. tostring(#task_queue))
        player_state.task_state = task.type
        repeat
            local ____switch9 = task.type
            local ____cond9 = ____switch9 == TaskStates.WALKING_TO_ENTITY
            if ____cond9 then
                player_state.parameters_walk_to_entity = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.WALKING_DIRECT
            if ____cond9 then
                player_state.parameters_walking_direct = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.MINING
            if ____cond9 then
                player_state.parameters_mine_entity = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.PLACING
            if ____cond9 then
                player_state.parameters_place_entity = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.MOVING_ITEMS
            if ____cond9 then
                player_state.parameters_move_items = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.CRAFTING
            if ____cond9 then
                do
                    local player = game.connected_players[1]
                    if not player then
                        log("[AUTORIO] No player found")
                        return
                    end
                    player.begin_crafting({count = task.count, recipe = task.item_name})
                    player_state.parameters_craft_item = task
                    break
                end
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.ATTACKING
            if ____cond9 then
                player_state.parameters_attack_nearest_enemy = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.RESEARCHING
            if ____cond9 then
                player_state.parameters_research_technology = task
                break
            end
            ____cond9 = ____cond9 or ____switch9 == TaskStates.WAITING
            if ____cond9 then
                player_state.parameters_waiting = task
                break
            end
        until true
    end
    player_state = {task_state = TaskStates.IDLE}
    task_queue = {}
    local function add_task(self, task)
        task_queue[#task_queue + 1] = task
        log((("[AUTORIO] Task added: " .. task.type) .. ", task queue length: ") .. tostring(#task_queue))
        if #task_queue == 1 then
            next_task(nil)
        end
    end
    local function reset_task_state(self)
	local player = game.connected_players[1]
        if player then
            player.walking_state = {walking = false}
        end
        player_state.task_state = TaskStates.IDLE
        player_state.parameters_walk_to_entity = nil
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
                    entities = {}
                }
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
                                table.insert(result.entities, {
                                    id = ent.unit_number or 0,
                                    name = ent.name,
                                    type = ent.type,
                                    x = math.floor(ent.position.x * 10) / 10,
                                    y = math.floor(ent.position.y * 10) / 10
                                })
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
local function __TS__ArrayForEach(self, callbackFn, thisArg)
    for i = 1, #self do
        callbackFn(thisArg, self[i], i - 1, self)
    end
end
local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
local function __TS__ArrayIsArray(value)
    return type(value) == "table" and (value[1] ~= nil or next(value) == nil)
end
local function __TS__ArrayFlat(self, depth)
    if depth == nil then depth = 1 end
    local result = {}
    local len = 0
    for i = 1, #self do
        local value = self[i]
        if depth > 0 and __TS__ArrayIsArray(value) then
            local toAdd = (depth == 1) and value or __TS__ArrayFlat(value, depth - 1)
            for j = 1, #toAdd do
                len = len + 1
                result[len] = toAdd[j]
            end
        else
            len = len + 1
            result[len] = value
        end
    end
    return result
end

local ____exports = {}
local check_can_craft
local ____task_manager = require("task_manager")
local new_task_manager = ____task_manager.new_task_manager
local ____tools = require("tools")
local create_tools_remote_interface = ____tools.create_tools_remote_interface
local ____types = require("types")
local TaskStates = ____types.TaskStates
local ____inventory = require("utils.inventory")
local get_inventory_items = ____inventory.get_inventory_items
local ____math = require("utils.math")
local distance = ____math.distance

function check_can_craft(self, player, item_name, count)
    local recipe = player.force.recipes[item_name]
    if not recipe then return false end
    local ingredients = recipe.ingredients
    local player_inventory = player.get_main_inventory()
    if not player_inventory then return false end
    for ____, ingredient in ipairs(ingredients) do
        local item_count = player_inventory.get_item_count(ingredient.name)
        if item_count < ingredient.amount * count then
            return false
        end
    end
    return true
end

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
            log((("[AUTORIO] New walk_to_entity task: " .. entity_name) .. ", radius: ") .. tostring(search_radius))
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
        wait = function(ticks)
            task_manager:add_task({type = TaskStates.WAITING, remaining_ticks = ticks})
            return {true, "Task started"}
        end,
        craft_item = function(item_name, count)
            if count == nil then count = 1 end
            local player = game.connected_players[1]
            if not player or not player.force.recipes[item_name] then
                return {false, "Recipe not available"}
            end
            if not player.force.recipes[item_name].enabled then
                return {false, "Recipe not unlocked"}
            end
            if not check_can_craft(nil, player, item_name, count) then
                return {false, "Not enough ingredients"}
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
            local player = game.connected_players[1]
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

    -- Если позиция задана жестко
    if params.position then
        start_mining(nil, player, params.position)
        return
    end

    -- Ищем цель в радиусе 15 тайлов
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

    -- Проверяем, достают ли руки персонажа до объекта
    if not player.can_reach_entity(nearest) then
        -- Дерево вне досягаемости: бежим к нему
        local dir = get_direction(nil, player.position, nearest.position)
        player.walking_state = {walking = true, direction = dir}
    else
        -- Дерево в досягаемости: тормозим и начинаем рубку
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
    if not item_stack then
        log("[AUTORIO] Entity not found in inventory: " .. params.entity_name)
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Entity not found in inventory"}
    end
    if not params.position then
        params.position = surface.find_non_colliding_position(params.entity_name, player.position, 1, 1)
        if not params.position then
            task_manager:reset_task_state()
            task_manager:next_task()
            return {false, "Could not find a valid position"}
        end
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
    
    -- Если передана точная координата цели, выбираем строго этот объект и Расширяем допуск до 1.5 тайла, чтобы попадать в центр зданий 2x2 и 3x3
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
    local player = game.connected_players[1]
    if player == nil or player.character == nil then return end
    local state = task_manager.player_state.task_state
    if state == TaskStates.IDLE then return end
    if state == TaskStates.WALKING_TO_ENTITY then state_walking_to_entity(nil, player)
    elseif state == TaskStates.MINING then state_mining(nil, player)
    elseif state == TaskStates.PLACING then state_placing(nil, player)
    elseif state == TaskStates.MOVING_ITEMS then state_moving_items(nil, player)
    elseif state == TaskStates.RESEARCHING then state_researching(nil, player)
    elseif state == TaskStates.WALKING_DIRECT then state_walking_direct(nil, player)
    elseif state == TaskStates.WAITING then state_waiting(nil)
    end
end)

script.on_event(defines.events.on_player_crafted_item, function(event)
    local params = task_manager.player_state.parameters_craft_item
    if not params or task_manager.player_state.task_state ~= TaskStates.CRAFTING then return end
    params.crafted = (params.crafted or 0) + 1
    if params.crafted >= params.count then
        task_manager:reset_task_state()
        task_manager:next_task()
    end
end)

log("[AUTORIO] Mod loaded (Enhanced Coordinates v2)")
return ____exports
 end,
["utils.hot_reload"] = function(...) return {} end,
["hot_reload"] = function(...) return {} end,
}
return require("control", ...)