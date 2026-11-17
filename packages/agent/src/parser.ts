export interface ChatMessage {
  type: 'chat'
  username: string
  message: string
  isServer: boolean
  date: string
}

export interface CommandMessage {
  type: 'command'
  username: string
  command: string
  isServer: boolean
  date: string
}

export interface ModErrorMessage {
  type: 'modError'
  serverTimestamp: string
  error: string
}

export interface OperationCompletedMessage {
  type: 'operationsCompleted'
  serverTimestamp: string
}

export type StdoutMessage = ChatMessage | CommandMessage | ModErrorMessage | OperationCompletedMessage

export interface LLMMessage {
  chatMessage: string
  operationCommands: string[]
  plan: string[]
  currentStep: number
}

export function parseLLMMessage(message: string): LLMMessage {
  let parsed: unknown
  try {
    parsed = JSON.parse(message)
  }
  catch (err) {
    throw new Error(`LLM replied with malformed JSON (${(err as Error).message})`)
  }

  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed))
    throw new Error('LLM reply is not a JSON object')

  // The model sometimes answers in its own shape (e.g. {"response": "..."}).
  // Without this check the agent silently sends nothing to the game: chatMessage
  // is undefined and operationCommands is missing.
  const candidate = parsed as Partial<Record<keyof LLMMessage, unknown>>
  const missing = (['plan', 'currentStep', 'chatMessage', 'operationCommands'] as const)
    .filter(key => candidate[key] === undefined)
  if (missing.length > 0)
    throw new Error(`LLM reply does not match the output contract, missing: ${missing.join(', ')}`)

  if (typeof candidate.chatMessage !== 'string')
    throw new Error('LLM reply has a non-string chatMessage')
  if (!Array.isArray(candidate.plan) || candidate.plan.some(step => typeof step !== 'string'))
    throw new Error('LLM reply has a non-array plan')
  if (!Array.isArray(candidate.operationCommands) || candidate.operationCommands.some(cmd => typeof cmd !== 'string'))
    throw new Error('LLM reply has a non-array operationCommands')
  if (typeof candidate.currentStep !== 'number' || !Number.isFinite(candidate.currentStep))
    throw new Error('LLM reply has a non-numeric currentStep')

  return {
    chatMessage: candidate.chatMessage,
    operationCommands: candidate.operationCommands,
    plan: candidate.plan,
    currentStep: candidate.currentStep,
  }
}

export function parseCommandMessage(log: string): CommandMessage | null {
  // example: 2025-02-02 12:08:24 [COMMAND] <server> (command): remote.call(\"autorio_tools\", \"get_recipe\", \"iron-chest\", 1)
  const serverRegex = /(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) \[COMMAND\] <server> \(command\): (.+)/
  const serverMatch = log.match(serverRegex)

  if (serverMatch) {
    const [, date, , command] = serverMatch
    return { username: 'server', command, isServer: true, date, type: 'command' }
  }

  // example: 2000-01-02 12:34:56 [COMMAND] username (command): log('hello world')
  const playerRegex = /(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) \[COMMAND\] (.+?) \(command\): (.+)/
  const playerMatch = log.match(playerRegex)

  if (playerMatch) {
    const [, date, , username, command] = playerMatch
    return { username, command, isServer: false, date, type: 'command' }
  }

  return null
}

export function parseChatMessage(log: string): ChatMessage | null {
  // example: 2000-01-02 12:34:56 [CHAT] <server>: message
  const serverChatRegex = /(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) \[CHAT\] <server>: (.+)/
  const serverMatch = log.match(serverChatRegex)

  if (serverMatch) {
    const [, date, , message] = serverMatch
    return { username: 'server', message, isServer: true, date, type: 'chat' }
  }

  // example: 2000-01-02 12:34:56 [CHAT] username: message
  const playerChatRegex = /(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) \[CHAT\] (.+?): (.+)/
  const playerMatch = log.match(playerChatRegex)

  if (playerMatch) {
    const [, date, , username, message] = playerMatch
    return { username, message, isServer: false, date, type: 'chat' }
  }

  return null
}

export function parseModErrorMessage(log: string): ModErrorMessage | null {
  // example: 42.535 Script @__autorio__/control.lua:661: [AUTORIO] [ERROR] No iron-ore found in 50m radius, reverting to IDLE state
  const modErrorRegex = /(\d+\.\d{3}) Script @__autorio__\/control\.lua:(\d+): \[AUTORIO\] \[ERROR\] (.+)/
  const modErrorMatch = log.match(modErrorRegex)

  if (modErrorMatch) {
    const [,serverTimestamp, , error] = modErrorMatch
    return { serverTimestamp, error, type: 'modError' }
  }

  return null
}

export function parseOperationCompletedMessage(log: string): OperationCompletedMessage | null {
  // example: 51.889 Script @__autorio__/control.lua:920: [AUTORIO] All operations completed
  const operationCompletedRegex = /(\d+\.\d{3}) Script @__autorio__\/control\.lua:(\d+): \[AUTORIO\] All operations completed/
  const operationCompletedMatch = log.match(operationCompletedRegex)

  if (operationCompletedMatch) {
    const [, serverTimestamp] = operationCompletedMatch
    return { serverTimestamp, type: 'operationsCompleted' }
  }

  return null
}
