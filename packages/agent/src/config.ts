import type { FactorioRconAPIClientConfig, FactorioWsConfig, OpenAIConfig } from './types.js'
import { env } from 'node:process'
import { useLogg } from '@guiiai/logg'

const logger = useLogg('config').useGlobalConfig()

export const DEFAULT_MODEL = 'deepseek/deepseek-v4.1-flash-1017'

/**
 * Parses `OPENROUTER_PROVIDER_ORDER`. Accepts either a comma-separated list
 * (`Morph,Relace`) or a JSON array (`["Morph","Relace"]`). An empty value means
 * "let OpenRouter route normally", so nothing is hardcoded in the source.
 */
export function parseProviderOrder(raw: string | undefined): string[] | undefined {
  const value = (raw ?? '').trim()
  if (!value)
    return undefined

  if (value.startsWith('{')) {
    logger.withFields({ value }).warn('OPENROUTER_PROVIDER_ORDER must be a comma-separated list or a JSON array; ignoring it')
    return undefined
  }

  if (value.startsWith('[')) {
    try {
      const parsed: unknown = JSON.parse(value)
      if (!Array.isArray(parsed)) {
        logger.withFields({ value }).warn('OPENROUTER_PROVIDER_ORDER starts with "[" but is not a JSON array; ignoring it')
        return undefined
      }
      const list = parsed
        .filter((entry): entry is string => typeof entry === 'string')
        .map(entry => entry.trim())
        .filter(Boolean)
      return list.length > 0 ? list : undefined
    }
    catch (err) {
      logger.withFields({ value, err }).warn('OPENROUTER_PROVIDER_ORDER is not valid JSON; ignoring it')
      return undefined
    }
  }

  const list = value.split(',').map(part => part.trim()).filter(Boolean)
  return list.length > 0 ? list : undefined
}

export const openaiConfig: OpenAIConfig & { model?: string } = {
  apiKey: '',
  baseUrl: '',
  model: DEFAULT_MODEL,
}

export const rconClientConfig: FactorioRconAPIClientConfig = {
  host: '',
  port: 0,
}

export const wsClientConfig: FactorioWsConfig = {
  wsHost: '',
  wsPort: 0,
}

export function initEnv() {
  logger.log('Initializing environment variables')

  openaiConfig.apiKey = env.OPENAI_API_KEY || ''
  openaiConfig.baseUrl = env.OPENAI_API_BASEURL || ''
  openaiConfig.model = env.OPENAI_MODEL_NAME || env.MODEL_NAME || DEFAULT_MODEL
  openaiConfig.providerOrder = parseProviderOrder(env.OPENROUTER_PROVIDER_ORDER)

  rconClientConfig.host = env.RCON_API_SERVER_HOST || 'localhost'
  rconClientConfig.port = Number.parseInt(env.RCON_API_SERVER_PORT || '24180')

  wsClientConfig.wsHost = env.FACTORIO_WS_HOST || 'localhost'
  wsClientConfig.wsPort = Number.parseInt(env.FACTORIO_WS_PORT || '8080')

  logger.withFields({ openaiConfig }).log('Environment variables initialized')
}
