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