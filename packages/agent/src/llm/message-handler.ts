import type { DefinedTool, Message } from 'neuri/openai'

import type { StdoutMessage } from '../parser'
import { createLogg } from '@guiiai/logg'
import { v2FactorioConsoleCommandRawPost } from 'factorio-rcon-api-client'
import { assistant, composeAgent, defineToolFunction, system, toolFunction, user } from 'neuri/openai'
import { openaiConfig } from '../config'
import { parseLLMMessage } from '../parser'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const prompt = readFileSync(join(__dirname, 'prompt.md'), 'utf-8')
import { tools } from './tools'

const logger = createLogg('agent').useGlobalConfig()

export async function createMessageHandler() {
  const toolFunctions: DefinedTool<any, any>[] = []

  for (const tool of tools) {
    toolFunctions.push(defineToolFunction(await toolFunction(tool.name, tool.description, tool.schema), tool.fn))
  }

  const agent = composeAgent({
    provider: {
      apiKey: openaiConfig.apiKey,
      baseURL: openaiConfig.baseUrl,
    },
    tools: toolFunctions,
  })

  const messages: Message[] = [system(prompt)]

  async function handleMessage(message: StdoutMessage) {
    logger.withFields({ message }).debug('Handling message')

    if (message.type === 'chat') {
      let currentObservation = ''
      try {
        const [scanRes, invRes] = await Promise.all([
          v2FactorioConsoleCommandRawPost({
            body: { input: '/sc remote.call("autorio_tools", "scan_entities", 25, 1)' },
          }),
          v2FactorioConsoleCommandRawPost({
            body: { input: '/sc remote.call("autorio_tools", "get_inventory_items", 1)' },
          }),
        ])

        currentObservation = `\n\n[Current Observation]:\nEntities & Player:\n${scanRes.data?.output || '{}'}\n\nInventory:\n${invRes.data?.output || '[]'}`
      }
      catch (err) {
        logger.withFields({ err }).warn('Failed to fetch automatic observation')
      }

      messages.push(user(`[CHAT] ${message.message}${currentObservation}`))
    }
    else if (message.type === 'modError') {
      messages.push(user(`[MOD] Error: ${message.error}`))
    }
    else if (message.type === 'operationsCompleted') {
      messages.push(user(`[MOD] All operations completed`))
    }

    const response = await agent.call(messages, {
      model: openaiConfig.model || 'gemini-3.5-flash-lite',
      maxRoundTrip: 5,
    })

    if (!response) {
      logger.withFields({ response }).error('LLM responded with null')
      return null
    }

    if (!response.choices || !response.choices.length) {
      logger.withFields({ response }).error('LLM responded with no choices')
      return null
    }

    const messageFromLLM = response.choices[0].message.content
    logger.withFields({ messageFromLLM }).debug('Message response from LLM')
    if (!messageFromLLM) {
      return null
    }

    // Очищаем ответ от маркдаун-оберток ```json ... ``` которые любят выдавать локальные модели
    const cleanedContent = messageFromLLM
      .replace(/^```json\s*/i, '')
      .replace(/^```\s*/i, '')
      .replace(/\s*```$/, '')
      .trim()

    const parsedMessage = parseLLMMessage(cleanedContent)
    messages.push(assistant(`${JSON.stringify(parsedMessage)}`))

    return parsedMessage
  }

  return {
    handleMessage,
  }
}

export type MessageHandler = Awaited<ReturnType<typeof createMessageHandler>>