export interface FactorioConfig {
  path: string
  savePath: string
  serverSettingsPath?: string
  rconPassword: string
  rconPort: number
}

export interface WsServerConfig {
  host: string
  port: number
}