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
    fn: async ({ parameters }) => {
      logger.withFields(parameters).debug('Try to get recipe for item')

      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "get_recipe", "${parameters.item}", 1)` },
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
    fn: async ({ parameters }) => {
      const radius = parameters?.radius || 25
      logger.withFields({ radius }).debug('Scanning entities around player')

      const response = await v2FactorioConsoleCommandRawPost({
        body: { input: `/sc remote.call("autorio_tools", "scan_entities", ${radius}, 1)` },
      })
      logger.withFields({ output: response.data?.output }).debug('Entities scanned')
      return response.data?.output || '{"player":{"x":0,"y":0},"entities":[]}'
    },
  },
]