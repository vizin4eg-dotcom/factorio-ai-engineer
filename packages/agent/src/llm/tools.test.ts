/* eslint-disable ts/naming-convention */
import { describe, expect, it } from 'vitest'
import { z } from 'zod'
import { tools } from './tools'

function isFlatSchema(schema: any): boolean {
  if (schema instanceof z.ZodString
    || schema instanceof z.ZodNumber
    || schema instanceof z.ZodBoolean
    || schema instanceof z.ZodEnum
    || schema instanceof z.ZodLiteral) {
    return true
  }
  if (schema instanceof z.ZodOptional || schema instanceof z.ZodDefault) {
    return isFlatSchema(schema.unwrap())
  }
  if (schema instanceof z.ZodUnion) {
    return (schema.options as any[]).every(isFlatSchema)
  }
  return false
}

function enumOptions(schema: any): string[] {
  expect(schema, 'expected an enum schema').toBeInstanceOf(z.ZodEnum)
  return [...schema.options] as string[]
}

describe('tool schemas', () => {
  it('keeps every tool schema flat', () => {
    expect(tools.length).toBeGreaterThan(0)
    for (const tool of tools) {
      expect(tool.schema, tool.name).toBeInstanceOf(z.ZodObject)
      const shape = (tool.schema as z.ZodObject<any>).shape
      for (const [field, fieldSchema] of Object.entries(shape)) {
        expect(isFlatSchema(fieldSchema), `${tool.name}.${field} must be a flat primitive, never an object or array`).toBe(true)
      }
    }
  })

  it('exposes armor grid management with the documented actions', () => {
    const armor = tools.find(tool => tool.name === 'manageArmorGrid')
    expect(armor, 'manageArmorGrid tool is missing').toBeDefined()
    const shape = (armor!.schema as z.ZodObject<any>).shape
    expect(enumOptions(shape.action)).toEqual(['inspect', 'equip', 'unequip', 'toggle_roboport'])
    expect(Object.keys(shape).sort()).toEqual([
      'action',
      'count',
      'enabled',
      'equipment_name',
      'x',
      'y',
    ])
  })

  it('exposes personal logistics management with the documented actions', () => {
    const logistics = tools.find(tool => tool.name === 'managePersonalLogistics')
    expect(logistics, 'managePersonalLogistics tool is missing').toBeDefined()
    const shape = (logistics!.schema as z.ZodObject<any>).shape
    expect(enumOptions(shape.action)).toEqual(['status', 'set_request', 'clear_request'])
    expect(Object.keys(shape).sort()).toEqual([
      'action',
      'item_name',
      'max_count',
      'min_count',
    ])
  })

  it('accepts flat arguments for the new tools', () => {
    const armor = tools.find(tool => tool.name === 'manageArmorGrid')!
    expect(armor.schema.parse({ action: 'equip', equipment_name: 'solar-panel', count: 2 })).toEqual({
      action: 'equip',
      equipment_name: 'solar-panel',
      count: 2,
    })
    const logistics = tools.find(tool => tool.name === 'managePersonalLogistics')!
    expect(logistics.schema.parse({
      action: 'set_request',
      item_name: 'iron-plate',
      min_count: 50,
      max_count: 200,
    })).toEqual({
      action: 'set_request',
      item_name: 'iron-plate',
      min_count: 50,
      max_count: 200,
    })
  })
})
