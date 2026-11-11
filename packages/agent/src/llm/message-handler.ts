import type { DefinedTool, Message } from 'neuri/openai'

import type { StdoutMessage } from '../parser'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createLogg } from '@guiiai/logg'
import { v2FactorioConsoleCommandRawPost } from 'factorio-rcon-api-client'
import { assistant, composeAgent, defineToolFunction, system, toolFunction, user } from 'neuri/openai'
import { tokenTracker } from '../../metrics'
import { DEFAULT_MODEL, openaiConfig } from '../config'
import { parseLLMMessage } from '../parser'
import { tools } from './tools'

const here = dirname(fileURLToPath(import.meta.url))
const prompt = readFileSync(join(here, 'prompt.md'), 'utf-8')

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
      // OpenRouter attribution: this is the app name shown in its activity table
      // (otherwise the column reads "Unknown").
      headers: {
        // Header names are fixed by the OpenRouter API.
        // eslint-disable-next-line ts/naming-convention
        'HTTP-Referer': 'https://github.com/vizin4eg-dotcom/factorio-ai-engineer',
        // eslint-disable-next-line ts/naming-convention
        'X-Title': 'Factorio AI Engineer',
      },
      // OpenRouter routing. neuri.call() forwards only model/maxRoundTrip, but xsai
      // spreads provider options into the request body (camelCase -> snake_case),
      // so the top-level `provider` field must live here.
      provider: {
        order: ['Relace'],
        // OpenRouter expects this field in snake_case.
        // eslint-disable-next-line ts/naming-convention
        allow_fallbacks: false,
      },
    } as Parameters<typeof composeAgent>[0]['provider'],
    tools: toolFunctions,
  })

  const messages: Message[] = [system(prompt)]

  async function handleMessage(message: StdoutMessage) {
    logger.withFields({ message }).debug('Handling message')

    if (message.type === 'chat') {
      let currentObservation = ''
      try {
        const [scanRes] = await Promise.all([
          v2FactorioConsoleCommandRawPost({
            body: { input: '/sc remote.call("autorio_tools", "scan_entities", 25, 1)' },
          }),
        ])

        currentObservation = `\n\n[Current Observation]:\nPlayer & nearby entities:\n${scanRes.data?.output || '{}'}\n\n(Inventory, base footprint and base threats are NOT prefetched. Call getInventoryItems / getMainBaseFootprint / getMainBaseThreats / getBaseTelemetry only when the request actually needs them.)`
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

    // Защита: отсекаем хвост модели при повторных попытках
    while (messages.length > 0 && messages[messages.length - 1].role === 'assistant') {
      messages.pop()
    }

    // Вызываем агента
    const response = await agent.call([...messages], {
      model: openaiConfig.model || DEFAULT_MODEL,
      maxRoundTrip: 5,
    })

    // Временная отладка: смотрим, что лежит в ответе агента
    // console.log('[DEBUG_RESPONSE]', JSON.stringify(response, null, 2))

    // Снимаем статистику токенов из ответа агента
    if (response) {
      // Провайдеры отдают usage в разных формах; neuri типизирует только snake_case.
      const usage = response.usage as unknown as Record<string, number | undefined> | undefined
      if (usage) {
        tokenTracker.recordUsage({
          promptTokens: usage.prompt_tokens ?? usage.promptTokens ?? usage.promptTokenCount,
          completionTokens: usage.completion_tokens ?? usage.completionTokens ?? usage.candidatesTokenCount,
        })
      }
    }

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
