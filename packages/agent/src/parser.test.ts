import { describe, expect, it } from 'vitest'
import { parseChatMessage, parseCommandMessage, parseLLMMessage, parseModErrorMessage, parseOperationCompletedMessage } from './parser'

describe('parseLLMMessage', () => {
  it('should accept the documented output contract', () => {
    const reply = JSON.stringify({ plan: ['step'], currentStep: 0, chatMessage: 'Привет!', operationCommands: [] })
    expect(parseLLMMessage(reply)).toEqual({ plan: ['step'], currentStep: 0, chatMessage: 'Привет!', operationCommands: [] })
  })

  it('should drop unknown extra keys but keep the contract', () => {
    const reply = JSON.stringify({ plan: [], currentStep: 0, chatMessage: 'ok', operationCommands: [], note: 'extra' })
    expect(parseLLMMessage(reply)).toEqual({ plan: [], currentStep: 0, chatMessage: 'ok', operationCommands: [] })
  })

  it('should reject a reply in the model\'s own shape', () => {
    expect(() => parseLLMMessage(JSON.stringify({ response: 'Привет' }))).toThrow(/missing: plan, currentStep, chatMessage, operationCommands/)
  })

  it('should reject malformed JSON', () => {
    expect(() => parseLLMMessage('not json')).toThrow(/malformed JSON/)
  })

  it('should reject wrong field types', () => {
    const reply = JSON.stringify({ plan: 'step', currentStep: '0', chatMessage: 'ok', operationCommands: [] })
    expect(() => parseLLMMessage(reply)).toThrow(/non-array plan/)
    const reply2 = JSON.stringify({ plan: [], currentStep: 0, chatMessage: 42, operationCommands: [] })
    expect(() => parseLLMMessage(reply2)).toThrow(/non-string chatMessage/)
    const reply3 = JSON.stringify({ plan: [], currentStep: 0, chatMessage: 'ok', operationCommands: 'x' })
    expect(() => parseLLMMessage(reply3)).toThrow(/non-array operationCommands/)
  })
})

describe('parseCommandMessage', () => {
  it('should parse player command', () => {
    const log = `2025-02-02 11:53:37 [COMMAND] username (command): remote.call("autorio_tools", "get_inventory_items", 1)`
    const result = parseCommandMessage(log)
    expect(result).toEqual({
      username: 'username',
      command: `remote.call("autorio_tools", "get_inventory_items", 1)`,
      isServer: false,
      date: '2025-02-02',
      type: 'command',
    })
  })

  it('should parse server command', () => {
    const log = `2025-02-02 12:03:17 [COMMAND] <server> (command): remote.call(\"autorio_tools\", \"get_inventory_items\", 1)`
    const result = parseCommandMessage(log)
    expect(result).toEqual({
      username: 'server',
      command: `remote.call("autorio_tools", "get_inventory_items", 1)`,
      isServer: true,
      date: '2025-02-02',
      type: 'command',
    })
  })
})

describe('parseChatMessage', () => {
  it('should parse chat message', () => {
    const log = `2025-02-02 11:53:37 [CHAT] username: hello world`
    const result = parseChatMessage(log)
    expect(result).toEqual({
      username: 'username',
      message: 'hello world',
      isServer: false,
      date: '2025-02-02',
      type: 'chat',
    })
  })

  it('should parse server chat message', () => {
    const log = `2025-02-02 11:53:37 [CHAT] <server>: hello world`
    const result = parseChatMessage(log)
    expect(result).toEqual({
      username: 'server',
      message: 'hello world',
      isServer: true,
      date: '2025-02-02',
      type: 'chat',
    })
  })
})

describe('parseModErrorMessage', () => {
  it('should parse mod error message', () => {
    const log = `42.535 Script @__autorio__/control.lua:661: [AUTORIO] [ERROR] No iron-ore found in 50m radius, reverting to IDLE state`
    const result = parseModErrorMessage(log)
    expect(result).toEqual({
      error: 'No iron-ore found in 50m radius, reverting to IDLE state',
      serverTimestamp: '42.535',
      type: 'modError',
    })
  })
})

describe('parseOperationCompletedMessage', () => {
  it('should parse operation completed message', () => {
    const log = `51.889 Script @__autorio__/control.lua:920: [AUTORIO] All operations completed`
    const result = parseOperationCompletedMessage(log)
    expect(result).toEqual({
      serverTimestamp: '51.889',
      type: 'operationsCompleted',
    })
  })
})
