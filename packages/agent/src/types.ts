export interface OpenAIConfig {
  apiKey: string
  baseUrl: string
  /** OpenRouter provider routing order; undefined keeps the default routing. */
  providerOrder?: string[]
}

export interface FactorioWsConfig {
  wsPort: number
  wsHost: string
}

export interface FactorioRconAPIClientConfig {
  port: number
  host: string
}
