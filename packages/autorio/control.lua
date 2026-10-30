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

local function restore_or_arm_companion(bot)
    if not (bot and bot.valid) then return end

    -- Если есть сохраненный лут с прошлого тела — возвращаем его
    if storage.saved_bot_items and #storage.saved_bot_items > 0 then
        for _, item in ipairs(storage.saved_bot_items) do
            bot.insert(item)
        end
        storage.saved_bot_items = nil
        log("[AUTORIO] Companion inventory restored from previous body")
    end

    -- Проверяем наличие оружия после восстановления
    local guns = bot.get_inventory(defines.inventory.character_guns)
    local ammo = bot.get_inventory(defines.inventory.character_ammo)

    if guns and guns.is_empty() then
        guns.insert({name = "submachine-gun", count = 1})
    end
    if ammo and ammo.is_empty() then
        ammo.insert({name = "firearm-magazine", count = 100})
    end
end

local function get_companion_body()
    -- 1. Быстрый возврат валидной ссылки
    if storage.bot and storage.bot.valid then
        return storage.bot
    end

    local player = get_target_player(1)
    local default_force = (player and player.force) or "player"

    -- 2. Ищем существующего компаньона по ВСЕМ поверхностям
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

    -- Вооружаем и восстанавливаем вещи новому телу!
    restore_or_arm_companion(storage.bot)

    return storage.bot
end

-- Обновление аккуратной радиометки на миникарте и карте мира
local function update_companion_map_tag(bot)
    if not (bot and bot.valid) then
        if storage.companion_chart_tag and storage.companion_chart_tag.valid then
            storage.companion_chart_tag.destroy()
            storage.companion_chart_tag = nil
        end
        return
    end

    if not (storage.companion_chart_tag and storage.companion_chart_tag.valid) then
        storage.companion_chart_tag = bot.force.add_chart_tag(bot.surface, {
            position = bot.position,
            text = "[color=0.3,0.7,1.0]Companion[/color]",
            icon = {type = "item", name = "modular-armor"}
        })
    else
        storage.companion_chart_tag.position = bot.position
    end
end

-- Автоматическая перекладка патронов и оружия из рюкзака в боевые слоты
local function auto_equip_combat_gear(bot)
    if not (bot and bot.valid) then return end

    local main_inv = bot.get_main_inventory()
    local guns_inv = bot.get_inventory(defines.inventory.character_guns)
    local ammo_inv = bot.get_inventory(defines.inventory.character_ammo)

    if not (main_inv and guns_inv and ammo_inv) then return end

    -- 1. Экипировка оружия (если слот пуст)
    if guns_inv.is_empty() then
        for i = 1, #main_inv do
            local stack = main_inv[i]
            if stack and stack.valid and stack.valid_for_read then
                local proto = prototypes.item[stack.name] or game.item_prototypes[stack.name]
                if proto and proto.type == "gun" then
                    local name = stack.name
                    if guns_inv.can_insert({name = name, count = 1}) then
                        local inserted = guns_inv.insert({name = name, count = 1})
                        if inserted > 0 then
                            main_inv.remove({name = name, count = inserted})
                            break
                        end
                    end
                end
            end
        end
    end

    -- 2. Дозарядка патронов в слот боеприпасов
    for i = 1, #main_inv do
        local stack = main_inv[i]
        if stack and stack.valid and stack.valid_for_read then
            local proto = prototypes.item[stack.name] or game.item_prototypes[stack.name]
            if proto and proto.type == "ammo" then
                local name = stack.name
                local count = stack.count
                local to_insert = {name = name, count = count}
                if ammo_inv.can_insert(to_insert) then
                    local inserted = ammo_inv.insert(to_insert)
                    if inserted > 0 then
                        main_inv.remove({name = name, count = inserted})
                    end
                end
            end
        end
    end
end

-- Боевая автооборона компаньона
local function process_companion_defense(bot, tick)
    -- Проверка каждые 6 тиков (10 выстрелов в секунду)
    if tick % 6 ~= 0 then return end
    if not (bot and bot.valid) then return end

    local enemies = bot.surface.find_entities_filtered{
        position = bot.position,
        radius = 18,
        force = "enemy"
    }
    if #enemies == 0 then return end
    
    -- Подтягиваем патроны и оружие из рюкзака в боевые слоты
    auto_equip_combat_gear(bot)

    -- Ищем первую валидную цель, обладающую здоровьем
    local target = nil
    for _, e in pairs(enemies) do
        if e.valid and e.is_entity_with_health and e.health and e.health > 0 then
            target = e
            break
        end
    end

    -- ЕСЛИ ЖИВОЙ ЦЕЛИ НЕТ — ПРЕКРАЩАЕМ ВЫПОЛНЕНИЕ:
    if not (target and target.valid) then return end

    -- Безопасный сброс ходьбы: проверяем, доступен ли task_manager
    if task_manager and task_manager.player_state then
        local cur_state = task_manager.player_state.task_state
        if storage.is_following and (cur_state == TaskStates.WALKING_TO_ENTITY or cur_state == TaskStates.WALKING_DIRECT) then
            task_manager:reset_task_state()
        end
    end
    
    -- В любом случае сразу останавливаем ноги бота для открытия огня
    local riding = false
    local ok_vehicle, ridden = pcall(function() return bot.vehicle end)
    if ok_vehicle and ridden and ridden.valid then riding = true end
    if storage.is_following and not riding then
        bot.walking_state = {walking = false}
    end

    -- Проверяем наличие патронов в слоте боеприпасов
    local ammo_inv = bot.get_inventory(defines.inventory.character_ammo)
    if not ammo_inv or ammo_inv.is_empty() then return end

    local ammo_stack = ammo_inv[1]
    if not (ammo_stack and ammo_stack.valid_for_read) then return end

    -- Поворачиваемся лицом к цели
    local angle = math.atan2(target.position.y - bot.position.y, target.position.x - bot.position.x)
    local octant = math.floor((angle + math.pi) / (2 * math.pi) * 8 + 0.5) % 8
    bot.direction = (octant * 2) % 16

    -- Наносим честный урон и тратим боеприпас
    target.damage(16, bot.force, "physical", bot)
    ammo_stack.drain_ammo(1)
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
    local items = {}
    if main_inventory then
        items = __TS__ArrayMap(
            main_inventory.get_contents(),
            function(____, binding)
                return {name = binding.name, count = binding.count}
            end
        )
    end
    local armor_name = "none"
    local armor_grid = {}
    local ainv = bot.get_inventory(defines.inventory.character_armor)
    if ainv and not ainv.is_empty() then
        local worn = ainv[1]
        if worn and worn.valid_for_read then
            armor_name = worn.name
            local grid = worn.grid
            if grid then
                local counts = {}
                for _, eq in pairs(grid.equipment) do
                    if eq and eq.name then
                        counts[eq.name] = (counts[eq.name] or 0) + 1
                    end
                end
                for name, count in pairs(counts) do
                    armor_grid[#armor_grid + 1] = {name = name, count = count}
                end
            end
        end
    end
    return {items = items, armor = armor_name, armor_grid = armor_grid}
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
____exports.TaskStates.EQUIPPING_MODULE = "equipping_module"
____exports.TaskStates.ENTERING_VEHICLE = "entering_vehicle"
____exports.TaskStates.DRIVING = "driving"
____exports.TaskStates.EXITING_VEHICLE = "exiting_vehicle"
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
            elseif switch_state == TaskStates.EQUIPPING_MODULE then
                player_state.parameters_equip_module = task
                break
            elseif switch_state == TaskStates.ENTERING_VEHICLE then
                player_state.parameters_enter_vehicle = task
                break
            elseif switch_state == TaskStates.DRIVING then
                player_state.parameters_driving = task
                break
            elseif switch_state == TaskStates.EXITING_VEHICLE then
                player_state.parameters_exit_vehicle = task
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
        player_state.parameters_equip_module = nil
        player_state.parameters_enter_vehicle = nil
        player_state.parameters_driving = nil
        player_state.parameters_exit_vehicle = nil
        player_state.parameters_build_ghosts = nil
    end

    local function is_task_queue_empty(self)
        return #task_queue == 0
    end

    local function cancel_task(self)
        reset_task_state(nil)
    end

    local function cancel_all_tasks(self)
        __TS__ArraySetLength(task_queue, 0)
        reset_task_state(nil)
        local bot = get_companion_body()
        if bot and bot.valid then
            bot.walking_state = {walking = false}
            local ok, vehicle = pcall(function() return bot.vehicle end)
            if ok and vehicle and vehicle.valid then
                pcall(function()
                    vehicle.riding_state = {
                        acceleration = defines.riding.acceleration.braking,
                        direction = defines.riding.direction.straight
                    }
                end)
            end
        end
    end

    return {
        player_state = player_state,
        add_task = add_task,
        next_task = next_task,
		task_queue = task_queue,
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
		follow_player = function()
			if storage.is_following then return true end
			storage.is_following = true
			game.print("[AI Companion]: Еду за тобой.")
			log("[AUTORIO] Follow mode enabled (autonomous)")
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
        equip_module = function(equipment_name, count)
            local n = tonumber(count)
            if count == "all" or count == "все" then n = 1000 end
            if n == nil then n = 1 end
            task_manager:add_task({
                type = TaskStates.EQUIPPING_MODULE,
                equipment_name = equipment_name or "",
                count = n,
                remove = false
            })
            log("[AUTORIO] Companion equip_module queued: " .. tostring(equipment_name) .. " x" .. tostring(n))
            return true
        end,
        remove_module = function(equipment_name, count)
            local n = tonumber(count)
            if count == "all" or count == "все" or equipment_name == "all" then n = 1000 end
            if n == nil then n = 1 end
            task_manager:add_task({
                type = TaskStates.EQUIPPING_MODULE,
                equipment_name = equipment_name or "",
                count = n,
                remove = true
            })
            log("[AUTORIO] Companion remove_module queued: " .. tostring(equipment_name))
            return true
        end,
        enter_vehicle = function(vehicle_name)
            local bot = get_companion_body()
            if bot and bot.valid then
                local ok, ridden = pcall(function() return bot.vehicle end)
                if ok and ridden and ridden.valid then return true end
            end
            task_manager:add_task({
                type = TaskStates.ENTERING_VEHICLE,
                vehicle_name = vehicle_name or "",
                tries = 0
            })
            game.print("[AI Companion]: Сажусь в " .. tostring((vehicle_name and vehicle_name ~= "") and vehicle_name or "транспорт") .. ".")
            log("[AUTORIO] Companion enter_vehicle queued: " .. tostring(vehicle_name))
            return true
        end,
        drive_to = function(x, y)
            if type(x) == "table" then y = x.y or x[2]; x = x.x or x[1] end
            local px, py = tonumber(x), tonumber(y)
            local human = get_target_player(1)
            local near_human = false
            if px and py and human and human.character and human.character.valid then
                local dx = human.character.position.x - px
                local dy = human.character.position.y - py
                near_human = dx * dx + dy * dy < 400
            end
            if (not px or not py) or storage.is_following or near_human then
                if not storage.is_following then
                    storage.is_following = true
                    game.print("[AI Companion]: Еду за тобой.")
                end
                return true
            end
            storage.is_following = false
            task_manager:add_task({
                type = TaskStates.DRIVING,
                target_position = {x = px, y = py},
                stuck = 0,
                tries = 0
            })
            game.print("[AI Companion]: Еду к точке.")
            return true
        end,
        exit_vehicle = function()
            task_manager:add_task({type = TaskStates.EXITING_VEHICLE})
            game.print("[AI Companion]: Выхожу.")
            log("[AUTORIO] Companion exit_vehicle queued")
            return true
        end,
        enterVehicle = function(vehicle_name)
            return remote.call("autorio_operations", "enter_vehicle", vehicle_name)
        end,
        driveTo = function(x, y)
            return remote.call("autorio_operations", "drive_to", x, y)
        end,
        exitVehicle = function()
            task_manager:add_task({type = TaskStates.EXITING_VEHICLE})
            game.print("[AI Companion]: Выхожу.")
            return true
        end,
        equipModule = function(equipment_name, count)
            local n = tonumber(count)
            if count == "all" or count == "все" then n = 1000 end
            if n == nil then n = 1 end
            task_manager:add_task({
                type = TaskStates.EQUIPPING_MODULE,
                equipment_name = equipment_name or "",
                count = n,
                remove = false
            })
            game.print("[AI Companion]: Ставлю модуль " .. tostring(equipment_name) .. ".")
            return true
        end,
        removeModule = function(equipment_name, count)
            local n = tonumber(count)
            if count == "all" or count == "все" or equipment_name == "all" then n = 1000 end
            if n == nil then n = 1 end
            task_manager:add_task({
                type = TaskStates.EQUIPPING_MODULE,
                equipment_name = equipment_name or "",
                count = n,
                remove = true
            })
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
            storage.is_following = false
            task_manager:cancel_all_tasks()
            return true
        end
    }
)

local function get_direction(self, start_position, end_position)
    local dx = end_position.x - start_position.x
    local dy = end_position.y - start_position.y
    if dx == 0 and dy == 0 then return defines.direction.north end
    local angle = math.atan2(dx, -dy)
    local dir = math.floor(angle / (2 * math.pi) * 16 + 16.5) % 16
    return (math.floor(dir / 2 + 0.5) * 2) % 16
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

            -- Если конкретный тайл руды, дерево или валун иссякли
            if not target.valid then
                params.current_target = nil
                params.collected_count = (params.collected_count or 0) + 1

                -- Проверка 1: достигнут ли лимит
                if params.target_count and params.collected_count >= params.target_count then
                    bot.walking_state = {walking = false}
                    task_manager:reset_task_state()
                    task_manager:next_task()
                    return
                end

                -- Проверка 2: ищем следующий ресурс поблизости
                local radius = params.search_radius or 30
                local target_names = params.target_names or {
                    "rock-huge", "rock-big", "sand-rock-big",
                    "tree-01", "tree-02", "tree-03", "tree-04", "tree-05",
                    "tree-06", "tree-07", "tree-08", "tree-09"
                }

                local next_targets = bot.surface.find_entities_filtered{
                    position = bot.position,
                    radius = radius,
                    name = target_names
                }

                if #next_targets > 0 then
                    params.current_target = next_targets[1]
                else
                    bot.walking_state = {walking = false}
                    task_manager:reset_task_state()
                    task_manager:next_task()
                    return
                end
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
    if not (bot and bot.valid) then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Invalid companion"}
    end

    local params = task_manager.player_state.parameters_place_entity
    if not params then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Missing place parameters"}
    end

    local surface = bot.surface
    local inventory = bot.get_main_inventory()
    if not inventory then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Cannot access companion inventory"}
    end

    -- 1. Проверяем наличие предмета через getItemCount
    if inventory.get_item_count(params.entity_name) == 0 then
        log("[AUTORIO] Entity not found in companion inventory: " .. tostring(params.entity_name))
        game.print("[AI Companion]: Cannot place '" .. tostring(params.entity_name) .. "' (not in bot inventory).")
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Item not in inventory"}
    end

    -- 2. Нормализация позиции (поддержка формата {x, y} и [x, y])
    local target_pos = params.position
    if not target_pos then
        target_pos = surface.find_non_colliding_position(params.entity_name, bot.position, 2, 0.5)
        params.position = target_pos
    end

    if not target_pos then
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Could not find a valid position"}
    end

    local px = target_pos.x or target_pos[1]
    local py = target_pos.y or target_pos[2]

    -- 3. Проверка дистанции (reach_distance): радиус до 8 клеток
    local dx = px - bot.position.x
    local dy = py - bot.position.y
    local dist_sq = dx * dx + dy * dy

    if dist_sq > 64.0 then -- дальше 8 клеток
        -- Бот ещё слишком далеко: делаем шаг ближе вместо фейла
        local dir = get_direction(nil, bot.position, {x = px, y = py})
        bot.walking_state = {walking = true, direction = dir}
        return {false, "Walking closer to placement site"}
    end

    -- Если дошли в радиус действия — глушим шаг
    bot.walking_state = {walking = false}

    -- 4. Проверка возможности установки
    local place_check = {
        name = params.entity_name,
        position = {x = px, y = py},
        direction = params.direction,
        force = bot.force
    }

    if not surface.can_place_entity(place_check) then
        local pos_str = string.format("(x=%.1f, y=%.1f)", px, py)
        log("[AUTORIO] Tile is occupied for " .. params.entity_name .. " at " .. pos_str)
        game.print("[AI Companion]: FAILED to place '" .. params.entity_name .. "' at " .. pos_str .. " - collision or occupied!")
        task_manager:reset_task_state()
        task_manager:next_task()
        return {false, "Tile is occupied"}
    end

    -- 5. Создание сущности
    local entity = surface.create_entity{
        name = params.entity_name,
        position = {x = px, y = py},
        direction = params.direction,
        force = bot.force,
        raise_built = true
    }

    if entity then
        -- Честно забираем 1 предмет из инвентаря
        inventory.remove({name = params.entity_name, count = 1})
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
	auto_equip_combat_gear(bot)
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

local function bot_vehicle(bot)
    local ok, vehicle = pcall(function() return bot.vehicle end)
    if ok and vehicle and vehicle.valid then return vehicle end
    return nil
end

local function same_driver(vehicle, bot)
    local ok, driver = pcall(function() return vehicle.get_driver() end)
    if not ok or not driver then return false end
    if driver == bot then return true end
    if driver.valid and bot.valid and driver.unit_number and driver.unit_number == bot.unit_number then return true end
    return false
end

local function occupied_by_other(vehicle, bot)
    local ok, driver = pcall(function() return vehicle.get_driver() end)
    if not ok or not driver then return false end
    return not same_driver(vehicle, bot)
end

local function normalize_vehicle_name(name)
    if not name or name == "" then return nil end
    local s = string.lower(tostring(name))
    if s == "car" or s == "машина" or s == "авто" then return "car" end
    if s == "tank" or s == "танк" then return "tank" end
    return s
end

local function find_free_vehicle(bot, vehicle_name)
    local wanted = normalize_vehicle_name(vehicle_name)
    local names = wanted and {wanted} or {"car", "tank"}
    local list = bot.surface.find_entities_filtered{position = bot.position, radius = 120, name = names}
    local best, best_d = nil, math.huge
    for _, v in ipairs(list) do
        if v.valid and v.force ~= game.forces.enemy and not occupied_by_other(v, bot) then
            local d = (v.position.x - bot.position.x)^2 + (v.position.y - bot.position.y)^2
            if d < best_d then best, best_d = v, d end
        end
    end
    return best
end

local FUELS = {"nuclear-fuel", "rocket-fuel", "solid-fuel", "coal", "wood"}
local function ensure_vehicle_fuel(bot, vehicle)
    local ok, fuel_inv = pcall(function() return vehicle.get_fuel_inventory() end)
    if not ok or not fuel_inv or fuel_inv.get_item_count() > 0 then return true end
    local main = bot.get_main_inventory()
    if not main then return false end
    for _, fuel in ipairs(FUELS) do
        if prototypes.item[fuel] and main.get_item_count(fuel) > 0 then
            local moved = fuel_inv.insert{name = fuel, count = math.min(main.get_item_count(fuel), 20)}
            if moved > 0 then main.remove{name = fuel, count = moved}; return true end
        end
    end
    return false
end

local function park_vehicle(vehicle)
    if not (vehicle and vehicle.valid) then return end
    pcall(function() vehicle.riding_state = {acceleration = defines.riding.acceleration.braking, direction = defines.riding.direction.straight} end)
    pcall(function() vehicle.speed = 0 end)
end

local function drive_toward(bot, vehicle, target, stop_dist)
    local tx = target and tonumber(target.x)
    local ty = target and tonumber(target.y)
    if not (vehicle and vehicle.valid and tx and ty) then return true end
    local dx, dy = tx - vehicle.position.x, ty - vehicle.position.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local speed = math.abs(vehicle.speed or 0)
    if dist <= stop_dist and speed < 0.05 then park_vehicle(vehicle); return true end
    local desired = math.atan2(dx, -dy)
    if desired < 0 then desired = desired + math.pi * 2 end
    local current = (vehicle.orientation or 0) * math.pi * 2
    local diff = desired - current
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    local turn = defines.riding.direction.straight
    if diff > 0.18 then turn = defines.riding.direction.right elseif diff < -0.18 then turn = defines.riding.direction.left end
    local accel = defines.riding.acceleration.accelerating
    if dist < (stop_dist + speed * 50) or (math.abs(diff) > 1.2 and speed > 0.08) then accel = defines.riding.acceleration.braking end
    pcall(function() vehicle.riding_state = {acceleration = accel, direction = turn} end)
    return false
end

local function script_drive(vehicle, target, stop_dist)
    local tx = target and tonumber(target.x)
    local ty = target and tonumber(target.y)
    if not (vehicle and vehicle.valid and tx and ty) then return true end
    local dx, dy = tx - vehicle.position.x, ty - vehicle.position.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist <= stop_dist then pcall(function() vehicle.speed = 0 end); return true end
    local desired = math.atan2(dx, -dy)
    if desired < 0 then desired = desired + math.pi * 2 end
    local orient = desired / (math.pi * 2)
    local cur = vehicle.orientation or 0
    local diff = orient - cur
    if diff > 0.5 then diff = diff - 1 elseif diff < -0.5 then diff = diff + 1 end
    pcall(function()
        vehicle.orientation = (cur + diff * 0.25) % 1
        local cap = vehicle.name == "tank" and 0.12 or 0.35
        vehicle.speed = math.abs(diff) > 0.08 and cap * 0.35 or math.min(cap, math.max(0.03, dist * 0.05))
    end)
    return false
end

local function stick_behind(bot, vehicle)
    local angle = (vehicle.orientation or 0) * math.pi * 2
    pcall(function() bot.teleport({x = vehicle.position.x - math.sin(angle) * 4, y = vehicle.position.y + math.cos(angle) * 4}) end)
    bot.walking_state = {walking = false}
end

local function try_enter_vehicle(bot, vehicle)
    if not (vehicle and vehicle.valid) then return false end
    if same_driver(vehicle, bot) or bot_vehicle(bot) == vehicle then
        storage.autorio_script_vehicle = nil
        bot.walking_state = {walking = false}
        game.print("[AI Companion]: Уже в " .. vehicle.name .. ".")
        return true
    end
    ensure_vehicle_fuel(bot, vehicle)
    bot.walking_state = {walking = false}
    local ok, err = pcall(function() vehicle.set_driver(bot) end)
    if same_driver(vehicle, bot) or bot_vehicle(bot) == vehicle then
        storage.autorio_script_vehicle = nil
        game.print("[AI Companion]: Сел в " .. vehicle.name .. ". Тело внутри.")
        return true
    end
    storage.autorio_script_vehicle = vehicle
    game.print("[AI Companion]: В кресло не пустил (" .. tostring(err) .. "). Веду снаружи.")
    stick_behind(bot, vehicle)
    return "script"
end

local function state_entering_vehicle(self, bot)
    local params = task_manager.player_state.parameters_enter_vehicle
    if not params then task_manager:reset_task_state(); task_manager:next_task(); return end
    local wanted = normalize_vehicle_name(params.vehicle_name)
    local current = bot_vehicle(bot)
    if current and (not wanted or current.name == wanted) then
        game.print("[AI Companion]: Уже сижу в " .. current.name .. ".")
        task_manager:reset_task_state(); task_manager:next_task(); return
    end
    local vehicle = find_free_vehicle(bot, params.vehicle_name)
    if not vehicle then
        game.print("[AI Companion]: Не вижу свободный " .. tostring(wanted or "tank/car") .. " в радиусе 120.")
        task_manager:reset_task_state(); task_manager:next_task(); return
    end
    try_enter_vehicle(bot, vehicle)
    task_manager:reset_task_state(); task_manager:next_task()
end

local function ridden_vehicle(bot)
    local inside = bot_vehicle(bot)
    if inside then return inside, false end
    local scripted = storage.autorio_script_vehicle
    if scripted and scripted.valid then return scripted, true end
    return nil, false
end

local function state_driving(self, bot)
    local params = task_manager.player_state.parameters_driving
    local tx = params and params.target_position and tonumber(params.target_position.x)
    local ty = params and params.target_position and tonumber(params.target_position.y)
    if not tx or not ty then
        storage.is_following = true
        game.print("[AI Companion]: Точки нет, еду за тобой.")
        task_manager:reset_task_state(); task_manager:next_task(); return
    end
    local vehicle, scripted = ridden_vehicle(bot)
    if not vehicle then
        vehicle = find_free_vehicle(bot, nil)
        if not vehicle then
            game.print("[AI Companion]: Ехать не на чем.")
            task_manager:reset_task_state(); task_manager:next_task(); return
        end
        if try_enter_vehicle(bot, vehicle) ~= "script" then scripted = false else scripted = true end
        vehicle = scripted and storage.autorio_script_vehicle or bot_vehicle(bot) or vehicle
    end
    local arrived
    if scripted then
        stick_behind(bot, vehicle)
        arrived = script_drive(vehicle, params.target_position, 3.5)
    else
        arrived = drive_toward(bot, vehicle, params.target_position, 3.5)
    end
    if arrived then task_manager:reset_task_state(); task_manager:next_task() end
end

local function state_exiting_vehicle(self, bot)
    local vehicle, scripted = ridden_vehicle(bot)
    if vehicle then
        park_vehicle(vehicle)
        if not scripted then pcall(function() vehicle.set_driver(nil) end) end
        storage.autorio_script_vehicle = nil
        game.print("[AI Companion]: Вышел из " .. vehicle.name .. ".")
    end
    task_manager:reset_task_state(); task_manager:next_task()
end

local function state_equipping_module(self, bot)
    game.print("[AI Companion]: Модули в этой сборке ставятся прежней логикой, команда принята.")
    task_manager:reset_task_state(); task_manager:next_task()
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

local function state_attacking(self, bot)
    if not bot or not bot.valid then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    local params = task_manager.player_state.parameters_attack_nearest_enemy
    if not params then
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end
	
	-- Подтягиваем патроны и оружие перед боем
    auto_equip_combat_gear(bot)
	
    -- 1. Проверяем патроны в инвентаре оружия
    local ammo_inv = bot.get_inventory(defines.inventory.character_ammo)
    local has_ammo = false
    if ammo_inv and not ammo_inv.is_empty() then
        for i = 1, #ammo_inv do
            local stack = ammo_inv[i]
            if stack and stack.valid_for_read and stack.count > 0 then
                has_ammo = true
                break
            end
        end
    end

    if not has_ammo then
        game.print("[AI Companion]: У меня нет патронов для атаки!")
        log("[AUTORIO] Attack aborted: out of ammo")
        bot.walking_state = {walking = false}
        bot.shooting_state = {state = defines.shooting.not_shooting}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    -- 2. Ищем ближайшего врага в заданном радиусе
    local radius = params.search_radius or 50
    local enemies = bot.surface.find_entities_filtered{
        position = bot.position,
        radius = radius,
        force = "enemy"
    }

    if #enemies == 0 then
        -- Врагов нет — сектор чист
        log("[AUTORIO] No enemies found in radius " .. radius)
        bot.walking_state = {walking = false}
        bot.shooting_state = {state = defines.shooting.not_shooting}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    -- Находим самого близкого врага
    local nearest_enemy = nil
    local min_dist_sq = radius * radius * 4
    for _, enemy in pairs(enemies) do
        if enemy.valid and enemy.health and enemy.health > 0 then
            local dist_sq = (enemy.position.x - bot.position.x)^2 + (enemy.position.y - bot.position.y)^2
            if dist_sq < min_dist_sq then
                min_dist_sq = dist_sq
                nearest_enemy = enemy
            end
        end
    end

    if not nearest_enemy then
        bot.walking_state = {walking = false}
        bot.shooting_state = {state = defines.shooting.not_shooting}
        task_manager:reset_task_state()
        task_manager:next_task()
        return
    end

    -- 3. Дистанция стрельбы (для стандартного оружия ~15-18 клеток)
    local shoot_dist_sq = 15.0 * 15.0

    if min_dist_sq > shoot_dist_sq then
        -- Враг далеко: бежим к нему
        local dir = get_direction(nil, bot.position, nearest_enemy.position)
        bot.walking_state = {walking = true, direction = dir}
        bot.shooting_state = {state = defines.shooting.not_shooting}
    else
        -- Враг на дистанции выстрела: останавливаемся и стреляем
        bot.walking_state = {walking = false}
        bot.shooting_state = {
            state = defines.shooting.shooting_selected,
            position = nearest_enemy.position
        }
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
    if not setup_complete and not (storage and storage.setup_complete) then 
        setup(nil)
    end

    local bot = get_companion_body()
    if bot == nil or not bot.valid then return end
    
	if bot.walking_state.walking then
    if not storage.last_pos then
        storage.last_pos = {x = bot.position.x, y = bot.position.y, ticks_stuck = 0}
    else
        local move_dist_sq = (bot.position.x - storage.last_pos.x)^2 + (bot.position.y - storage.last_pos.y)^2
        if move_dist_sq < 0.01 then
            storage.last_pos.ticks_stuck = storage.last_pos.ticks_stuck + 1
        else
            storage.last_pos.x = bot.position.x
            storage.last_pos.y = bot.position.y
            storage.last_pos.ticks_stuck = 0
        end

        -- Если уперся и бежит на месте больше 20 тиков (треть секунды)
        if storage.last_pos.ticks_stuck > 20 then
            -- Сдвигаем направление по часовой стрелке, пытаясь обойти угол
            bot.walking_state = {
                walking = true, 
                direction = (bot.walking_state.direction + 2) % 16
            }
        end
	end
	else
		storage.last_pos = nil
	end
	
    local riding_now = false
    do
        local ok_vehicle, ridden = pcall(function() return bot.vehicle end)
        riding_now = ok_vehicle and ridden and ridden.valid
    end
    if riding_now then
        storage.evasion_ticks = nil
    elseif storage.evasion_ticks and storage.evasion_ticks > 0 then
        storage.evasion_ticks = storage.evasion_ticks - 1
        bot.walking_state = {walking = true, direction = storage.evasion_direction}
        return
    elseif storage.evasion_ticks == 0 then
        storage.evasion_ticks = nil
        bot.walking_state = {walking = false}
    end
    
    update_companion_map_tag(bot)
    process_companion_defense(bot, game.tick)
    
    local state = task_manager.player_state.task_state
    if state == TaskStates.IDLE then
        local idle_vehicle, idle_script = ridden_vehicle(bot)
        if idle_vehicle then
            if storage.is_following then
                local human = get_target_player(1)
                local pos = human and human.character and human.character.valid and human.character.position
                if pos and tonumber(pos.x) and tonumber(pos.y) then
                    if idle_script then
                        stick_behind(bot, idle_vehicle)
                        script_drive(idle_vehicle, pos, 6)
                    else
                        drive_toward(bot, idle_vehicle, pos, 6)
                    end
                end
            else
                park_vehicle(idle_vehicle)
            end
            return
        end
        if storage.is_following then
            local human = get_target_player(1)
            if human and human.character and human.character.valid then
                local nearby_enemies = bot.surface.find_entities_filtered{
                    position = bot.position,
                    radius = 24,
                    force = "enemy",
                    limit = 1
                }
                local player_in_combat = human.character.shooting_state.state ~= defines.shooting.not_shooting

                if #nearby_enemies > 0 or player_in_combat then
                    bot.walking_state = {walking = false}
                else
                    local dx = human.character.position.x - bot.position.x
                    local dy = human.character.position.y - bot.position.y
                    local dist_sq = dx * dx + dy * dy

                    if dist_sq > 36.0 then
                        local dir = get_direction(nil, bot.position, human.character.position)
                        bot.walking_state = {walking = true, direction = dir}
                    elseif dist_sq < 12.25 then
                        bot.walking_state = {walking = false}
                    end
                end
            end
        end
        return
    end

    if state == TaskStates.WALKING_TO_ENTITY then state_walking_to_entity(nil, bot)
    elseif state == TaskStates.MINING then state_mining(nil, bot)
    elseif state == TaskStates.PLACING then state_placing(nil, bot)
    elseif state == TaskStates.MOVING_ITEMS then state_moving_items(nil, bot)
    elseif state == TaskStates.BUILDING_GHOSTS then state_building_ghosts(nil, bot)
    elseif state == TaskStates.RESEARCHING then state_researching(nil, bot)
    elseif state == TaskStates.WALKING_DIRECT then state_walking_direct(nil, bot)
    elseif state == TaskStates.ATTACKING then state_attacking(nil, bot)
    elseif state == TaskStates.WAITING then state_waiting(nil)
    elseif state == TaskStates.EQUIPPING_ARMOR then state_equipping_armor(nil, bot)
    elseif state == TaskStates.EQUIPPING_MODULE then state_equipping_module(nil, bot)
    elseif state == TaskStates.ENTERING_VEHICLE then state_entering_vehicle(nil, bot)
    elseif state == TaskStates.DRIVING then state_driving(nil, bot)
    elseif state == TaskStates.EXITING_VEHICLE then state_exiting_vehicle(nil, bot)
    elseif state == TaskStates.CRAFTING then state_crafting(nil, bot)
    end
end)

script.on_event(defines.events.on_entity_damaged, function(event)
    local entity = event.entity
    if not (entity and entity.valid) then return end

    local bot = get_companion_body()
    if not (bot and bot.valid) or entity ~= bot then return end

    -- Если уже уворачиваемся, не сбиваем текущий маневр каждым тиком кислоты
    if storage.evasion_ticks and storage.evasion_ticks > 0 then return end

    local cause = event.cause
    local evade_angle

    if cause and cause.valid then
        -- Вектор ОТ червя к боту (направление бегства)
        local dx = bot.position.x - cause.position.x
        local dy = bot.position.y - cause.position.y
        -- Добавляем легкое боковое смещение (+/- 45 градусов), чтобы не пятиться строго по прямой
        local side_bias = (game.tick % 2 == 0) and 0.8 or -0.8
        evade_angle = math.atan2(dy, dx) + side_bias
    else
        -- Если урон от лужи под ногами: бежим строго назад от текущего взгляда
        evade_angle = math.atan2(bot.position.y, bot.position.x) + math.pi
    end

    local octant = math.floor((evade_angle + math.pi) / (2 * math.pi) * 8 + 0.5) % 8
    local evade_dir = (octant * 2) % 16

    -- Задаем импульс уклонения на 15 тиков (четверть секунды чистого отскока)
    storage.evasion_ticks = 15
    storage.evasion_direction = evade_dir
    bot.walking_state = {walking = true, direction = evade_dir}
end)

script.on_event(defines.events.on_entity_died, function(event)
    local entity = event.entity
    if not (entity and entity.valid and entity.type == "character" and entity.player == nil) then
        return
    end

    -- Сохраняем всё, что было у бота перед созданием трупа
    storage.saved_bot_items = {}
    
    local function save_inv(inv_id)
        local inv = entity.get_inventory(inv_id)
        if inv and not inv.is_empty() then
            for i = 1, #inv do
                local stack = inv[i]
                if stack and stack.valid_for_read then
                    table.insert(storage.saved_bot_items, {name = stack.name, count = stack.count})
                end
            end
        end
    end

    save_inv(defines.inventory.character_main)
    save_inv(defines.inventory.character_guns)
    save_inv(defines.inventory.character_ammo)
    save_inv(defines.inventory.character_armor)
    
    log("[AUTORIO] Companion died, saved " .. #storage.saved_bot_items .. " item stacks")
end)

log("[AUTORIO] Mod loaded (Autonomous Companion Architecture v13 chase)")
return ____exports
 end,
["utils.hot_reload"] = function(...) return {} end,
["hot_reload"] = function(...) return {} end,
}
return require("control", ...)