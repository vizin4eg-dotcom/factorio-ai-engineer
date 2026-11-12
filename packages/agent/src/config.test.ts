import { describe, expect, it } from 'vitest'
import { parseProviderOrder } from './config'

describe('parseProviderOrder', () => {
  it('returns undefined for missing or empty values', () => {
    expect(parseProviderOrder(undefined)).toBeUndefined()
    expect(parseProviderOrder('')).toBeUndefined()
    expect(parseProviderOrder('   ')).toBeUndefined()
    expect(parseProviderOrder(',')).toBeUndefined()
  })

  it('parses a comma-separated list and trims entries', () => {
    expect(parseProviderOrder('Morph')).toEqual(['Morph'])
    expect(parseProviderOrder(' Morph , Relace ')).toEqual(['Morph', 'Relace'])
    expect(parseProviderOrder('Morph,,Relace,')).toEqual(['Morph', 'Relace'])
  })

  it('parses a JSON array', () => {
    expect(parseProviderOrder('["Morph","Relace"]')).toEqual(['Morph', 'Relace'])
    expect(parseProviderOrder('[ "Morph" ]')).toEqual(['Morph'])
  })

  it('ignores non-string entries in a JSON array', () => {
    expect(parseProviderOrder('["Morph",1,null]')).toEqual(['Morph'])
    expect(parseProviderOrder('[1,2]')).toBeUndefined()
  })

  it('ignores malformed JSON instead of guessing', () => {
    expect(parseProviderOrder('["Morph",')).toBeUndefined()
    expect(parseProviderOrder('{"order":["Morph"]}')).toBeUndefined()
  })
})
