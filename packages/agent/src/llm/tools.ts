import { createLogg } from '@guiiai/logg'
import { v2FactorioConsoleCommandRawPost } from 'factorio-rcon-api-client'
import { z } from 'zod'

const logger = createLogg('tools').useGlobalConfig()

interface ToolFunction {
  name: string
  description: string
  schema: z.Schema
  fn: (args: any) => Promise<any>
}

export const tools: ToolFunction[] = [
  {
    name: 'getInventoryItems',
    description: 'Get the items in the player\'s inventory',
    schema: z.object({}),
    fn: async () => {
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_tools", "get_inventory_items", 1)' },
      })
      logger.withFields({ response: response.data?.output }).debug('Inventory items')
      return response.data?.output || ''
    },
  },
  {
    name: 'tagSelectedEntity',
    description: 'Tag and monitor the entity currently selected/hovered by the player cursor. Use for remembering key infrastructure like reactors, input/output belts, and fluid tanks.',
    schema: z.object({
      label: z.string().describe('Human-readable unique name for this node (e.g. "Реактор 1", "Вход Плавильни 1", "Нефть Север")'),
      category: z.enum(['critical', 'production', 'temporary']).optional().describe('Monitoring priority category. Defaults to critical.'),
    }),
    fn: async ({ label, category }) => {
      logger.withFields({ label, category }).debug('Tagging selected entity')
      const catArg = category || 'critical'
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "tag_selected_entity", "${label}", "${catArg}", 1)` },
      })
      logger.withFields({ response: response.data?.output }).debug('Entity tagged result')
      return response.data?.output || '{"status":"unknown"}'
    },
  },
  {
    name: 'getRecipe',
    description: 'Get the recipe for a given item',
    schema: z.object({
      item: z.string().describe('The item to get the recipe for'),
    }),
    fn: async ({ item }) => {
      const name = String(item ?? '').replace(/["\\]/g, '')
      logger.withFields({ item: name }).debug('Try to get recipe for item')

      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "get_recipe", "${name}", 1)` },
      })
      logger.withFields({ response: response.data?.output }).debug('Recipe')
      return response.data?.output || ''
    },
  },
  {
    name: 'getBaseTelemetry',
    description: 'Get base telemetry including power grid status, boiler fuel alerts, key production rates, and logistic network robot statistics.',
    schema: z.object({}),
    fn: async () => {
      logger.debug('Fetching base telemetry')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_tools", "get_base_telemetry", 1)' },
      })
      logger.withFields({ output: response.data?.output }).debug('Base telemetry received')
      return response.data?.output || '{}'
    },
  },
  {
    name: 'scanEntities',
    description: 'Scan surrounding area to get player current coordinates (player.x, player.y) and nearby entities',
    schema: z.object({
      radius: z.number().default(25).describe('Scanning radius in tiles around the player'),
    }),
    fn: async ({ radius }) => {
      const scanRadius = Number(radius) > 0 ? Number(radius) : 25
      logger.withFields({ radius: scanRadius }).debug('Scanning entities around player')

      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "scan_entities", ${scanRadius}, 1)` },
      })
      logger.withFields({ output: response.data?.output }).debug('Entities scanned')
      return response.data?.output || '{"player":{"x":0,"y":0},"entities":[]}'
    },
  },
  {
    name: 'equipModule',
    description: 'Insert equipment into the companion armor grid. Armor with a grid must already be worn, and the module must be in the companion inventory. Not for crafting modules like speed-module.',
    schema: z.object({
      name: z.string().describe('Equipment item name, e.g. solar-panel-equipment, battery-equipment, exoskeleton-equipment, personal-roboport-equipment, energy-shield-equipment, fusion-reactor-equipment. Short aliases like solar-panel, battery, exoskeleton also work. Empty string inserts every equipment item in inventory.'),
      count: z.union([z.number(), z.literal('all')]).optional().describe('How many to insert. Defaults to 1. "all" fills the grid.'),
    }),
    fn: async ({ name, count }) => {
      const item = String(name ?? '').replace(/["\\]/g, '')
      const countArg = count === undefined ? '1' : (typeof count === 'number' ? String(count) : '"all"')
      logger.withFields({ name: item, count }).debug('Equipping armor module')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "equip_module", "${item}", ${countArg})` },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'removeModule',
    description: 'Remove equipment from the companion armor grid back into inventory.',
    schema: z.object({
      name: z.string().describe('Equipment name to remove, or "all" to strip the grid.'),
      count: z.union([z.number(), z.literal('all')]).optional().describe('How many to remove. Defaults to 1.'),
    }),
    fn: async ({ name, count }) => {
      const item = String(name ?? 'all').replace(/["\\]/g, '')
      const countArg = count === undefined ? '1' : (typeof count === 'number' ? String(count) : '"all"')
      logger.withFields({ name: item, count }).debug('Removing armor module')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "remove_module", "${item}", ${countArg})` },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'manageArmorGrid',
    description: 'Inspect or change the companion armor equipment grid. inspect returns grid size, installed modules with positions, energy/shield totals and construction robot counts. equip/unequip move modules between inventory and grid. toggle_roboport enables or disables personal construction robot dispatch. Returns JSON.',
    schema: z.object({
      action: z.enum(['inspect', 'equip', 'unequip', 'toggle_roboport']).describe('inspect = read the grid; equip/unequip = move equipment; toggle_roboport = enable or disable personal construction robots.'),
      // eslint-disable-next-line ts/naming-convention
      equipment_name: z.string().optional().describe('Equipment name, e.g. solar-panel-equipment, battery-equipment, personal-roboport-equipment, exoskeleton-equipment. Short aliases like solar-panel also work. Use "all" to strip the grid on unequip.'),
      count: z.number().optional().describe('How many modules to equip or unequip. Defaults to 1.'),
      x: z.number().optional().describe('Optional grid x for the module. Omit to auto-place.'),
      y: z.number().optional().describe('Optional grid y for the module. Omit to auto-place.'),
      enabled: z.boolean().optional().describe('For toggle_roboport: true or false to force a state. Omit to toggle.'),
    }),
    fn: async (args: any) => {
      const what = String(args.action ?? 'inspect').replace(/["\\]/g, '')
      const item = String(args.equipment_name ?? '').replace(/["\\]/g, '')
      const count = args.count
      const x = args.x
      const y = args.y
      const enabled = args.enabled
      const countArg = count === undefined ? '1' : String(Math.trunc(Number(count)))
      const xArg = x === undefined ? '-1' : String(Number(x))
      const yArg = y === undefined ? '-1' : String(Number(y))
      const enabledArg = enabled === undefined ? '""' : (enabled ? 'true' : 'false')
      logger.withFields({ action: what, name: item, count: countArg, x: xArg, y: yArg, enabled }).debug('Managing armor grid')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "manage_armor_grid", "${what}", "${item}", ${countArg}, ${xArg}, ${yArg}, ${enabledArg})` },
      })
      return response.data?.output || '{"ok":false,"error":"no output"}'
    },
  },
  {
    name: 'managePersonalLogistics',
    description: 'Inspect or change the companion personal logistic requests. status returns network coverage, robot counts, the nearest roboport when outside coverage, active requests and trash contents. set_request asks the logistic network to keep an item stocked and can auto-trash the excess. clear_request removes the request. Returns JSON.',
    schema: z.object({
      action: z.enum(['status', 'set_request', 'clear_request']).describe('status = read requests and network; set_request = add or update a request; clear_request = remove a request.'),
      // eslint-disable-next-line ts/naming-convention
      item_name: z.string().optional().describe('Item name for set_request/clear_request, e.g. iron-plate, construction-robot, firearm-magazine.'),
      // eslint-disable-next-line ts/naming-convention
      min_count: z.number().optional().describe('Minimum amount to keep in the inventory. Defaults to 0.'),
      // eslint-disable-next-line ts/naming-convention
      max_count: z.number().optional().describe('Optional auto-trash threshold: excess above this is sent to trash. Omit for no auto-trash.'),
    }),
    fn: async (args: any) => {
      const what = String(args.action ?? 'status').replace(/["\\]/g, '')
      const item = String(args.item_name ?? '').replace(/["\\]/g, '')
      const minCount = args.min_count
      const maxCount = args.max_count
      const minArg = minCount === undefined ? '-1' : String(Math.trunc(Number(minCount)))
      const maxArg = maxCount === undefined ? '-1' : String(Math.trunc(Number(maxCount)))
      logger.withFields({ action: what, item, min: minArg, max: maxArg }).debug('Managing personal logistics')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "manage_personal_logistics", "${what}", "${item}", ${minArg}, ${maxArg})` },
      })
      return response.data?.output || '{"ok":false,"error":"no output"}'
    },
  },
  {
    name: 'enterVehicle',
    description: 'Walk to a free car or tank and become the driver. Does not steal an occupied vehicle. Loads fuel from the companion inventory if the vehicle is empty.',
    schema: z.object({
      name: z.string().optional().describe('car, tank, машина, танк, or empty for the nearest free vehicle.'),
    }),
    fn: async ({ name }) => {
      const vehicle = String(name ?? '').replace(/["\\]/g, '')
      logger.withFields({ name: vehicle }).debug('Entering vehicle')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "enter_vehicle", "${vehicle}")` },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'driveTo',
    description: 'Drive the car or tank to a coordinate. If the companion is on foot, it enters the nearest free car or tank first.',
    schema: z.object({
      x: z.number().describe('Target x'),
      y: z.number().describe('Target y'),
    }),
    fn: async ({ x, y }) => {
      logger.withFields({ x, y }).debug('Driving vehicle')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "drive_to", ${Number(x)}, ${Number(y)})` },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'exitVehicle',
    description: 'Brake and get out of the current car or tank.',
    schema: z.object({}),
    fn: async () => {
      logger.debug('Exiting vehicle')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_operations", "exit_vehicle")' },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'startAdvisor',
    description: 'Start the factory advisor. Lua counts shortages and prints them in chat. The model does not calculate rates.',
    schema: z.object({}),
    fn: async () => {
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_operations", "start_advisor")' },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'stopAdvisor',
    description: 'Stop the factory advisor. Does not stop movement.',
    schema: z.object({}),
    fn: async () => {
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_operations", "stop_advisor")' },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'factoryReport',
    description: 'Run one factory check now. Lua prints the shortage line and returns the report. Do not invent production numbers.',
    schema: z.object({}),
    fn: async () => {
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_operations", "factory_report")' },
      })
      return response.data?.output || '{}'
    },
  },
  {
    name: 'scanPatch',
    description: 'Measure the nearest ore patch. Returns tile count, ore amount and width x height. Lua prints the same line in chat.',
    schema: z.object({
      name: z.string().optional().describe('iron-ore, copper-ore, coal, stone, uranium-ore, or a Russian alias. Empty picks the nearest ore.'),
    }),
    fn: async ({ name }) => {
      const ore = String(name ?? '').replace(/["\\]/g, '')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "scan_patch", "${ore}")` },
      })
      return response.data?.output || '{}'
    },
  },
  {
    name: 'minePatch',
    description: 'Build the nearest ore patch with electric mining drills, transport belts and medium electric poles. Lua plans the layout. Missing items become ghosts.',
    schema: z.object({
      name: z.string().optional().describe('iron-ore, copper-ore, coal, stone, uranium-ore, or a Russian alias.'),
    }),
    fn: async ({ name }) => {
      const ore = String(name ?? '').replace(/["\\]/g, '')
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "mine_patch", "${ore}")` },
      })
      return response.data?.output || 'true'
    },
  },
  {
    name: 'getMainBaseFootprint',
    description: 'Returns the footprint of the main base only (ignores distant outposts). Includes center, bounds and approx radius.',
    schema: z.object({}),
    fn: async () => {
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: '/sc remote.call("autorio_tools", "get_main_base_footprint")' },
      })
      return response.data?.output || '{}'
    },
  },
  {
    name: 'getMainBaseThreats',
    description: 'Returns enemy nests and worms that are close to the main base (within given distance).',
    schema: z.object({
      maxDistance: z.number().optional().describe('Max distance from the main base edge. Default 60.'),
    }),
    fn: async ({ maxDistance }) => {
      const d = maxDistance ?? 60
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "get_main_base_threats", ${d})` },
      })
      return response.data?.output || '[]'
    },
  },
  {
    name: 'clearThreatsToMainBase',
    description: 'Clear enemy nests and worms threatening the main base. If threats are serious (worms or high evolution), the companion will use a tank. Only for the main base, ignores distant outposts.',
    schema: z.object({
      maxDistance: z.number().optional().describe('How far from the main base to consider threats. Default 60 tiles.'),
    }),
    fn: async ({ maxDistance }) => {
      const d = maxDistance ?? 60
      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_operations", "clear_threats_to_main_base", ${d})` },
      })
      return response.data?.output || 'true'
    },
  },
]
