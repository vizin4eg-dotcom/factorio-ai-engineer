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
        // Provider routing comes from OPENROUTER_PROVIDER_ORDER so switching a
        // provider never needs a source edit. Unset => OpenRouter default routing.
        ...(openaiConfig.providerOrder?.length ? { order: openaiConfig.providerOrder } : {}),
        // OpenRouter expects this field in snake_case.
        // eslint-disable-next-line ts/naming-convention
        allow_fallbacks: false,
      },
    } as Parameters<typeof composeAgent>[0]['provider'],
    tools: toolFunctions,
  })

  const messages: Message[] = [system(prompt)]

  /**
   * Queue a user turn, skipping an exact repeat of the previous one: a retry in
   * main.ts re-delivers the same event, and duplicated turns derail the model.
   */
  function pushUser(content: string) {
    const last = messages[messages.length - 1]
    if (last?.role === 'user' && typeof last.content === 'string' && last.content === content)
      return
    messages.push(user(content))
  }

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

      pushUser(`[CHAT] ${message.message}${currentObservation}`)
    }
    else if (message.type === 'modError') {
      pushUser(`[MOD] Error: ${message.error}`)
    }
    else if (message.type === 'operationsCompleted') {
      pushUser(`[MOD] All operations completed`)
    }

    // Защита: отсекаем хвост модели при повторных попытках
    while (messages.length > 0 && messages[messages.length - 1].role === 'assistant') {
      messages.pop()
    }

    // The model occasionally answers in its own shape ({"response": "..."}) or
    // wraps the reply in prose. One correction round is cheaper than letting the
    // turn die: the wrong reply is shown back to the model with the contract.
    for (let attempt = 1; attempt <= 2; attempt++) {
      const response = await agent.call([...messages], {
        model: openaiConfig.model || DEFAULT_MODEL,
        maxRoundTrip: 5,
      })

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

      try {
        const parsedMessage = parseLLMMessage(cleanedContent)
        messages.push(assistant(`${JSON.stringify(parsedMessage)}`))
        return parsedMessage
      }
      catch (err) {
        const reason = (err as Error).message
        logger.withFields({ attempt, reason }).warn('LLM reply rejected')
        // This line is the only trace the user sees when the agent goes silent.
        logger.error(`LLM reply rejected: ${reason}`)
        if (attempt === 2)
          return null

        pushUser(`[SYSTEM] Your previous reply was rejected: ${reason}. Reply again with ONLY the raw JSON object, all four keys: {"plan": [...], "currentStep": 0, "chatMessage": "...", "operationCommands": [...]}.`)
      }
    }

    return null
  }

  return {
    handleMessage,
  }
}

export type MessageHandler = Awaited<ReturnType<typeof createMessageHandler>>
