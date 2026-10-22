import type { ResultPromise } from 'execa'
import { arch } from 'node:os'
import process from 'node:process'
import { Format, setGlobalFormat, useLogg } from '@guiiai/logg'
import { execa } from 'execa'
import { WebSocketServer } from 'ws'
import { factorioConfig, initEnv, wsServerConfig } from './config'

setGlobalFormat(Format.Pretty)
const logger = useLogg('main').useGlobalConfig()

async function main() {
  initEnv()

  const gameLogger = useLogg('game').useGlobalConfig()
  const webSocketLogger = useLogg('webSocket').useGlobalConfig()

  const wsServer = new WebSocketServer({
    host: wsServerConfig.host,
    port: wsServerConfig.port,
  })

  wsServer.on('connection', (client) => {
    webSocketLogger.withFields({ clientId: client.url }).log('Client connected')
  })

  wsServer.on('error', (error) => {
    webSocketLogger.withFields({ error: error.message }).error('WebSocket server error')
  })

  wsServer.on('close', () => {
    webSocketLogger.log('Server closed')
  })

  // TODO: create a http server to receive mod change signal and restart factorio
  let factorioInst: ResultPromise<{
    stdout: ('pipe' | 'inherit')[]
  }>

  // Проверяем аргумент командной строки (argv[2])
  const saveArg = process.argv[2]
  let savePathToUse = factorioConfig.savePath

  if (saveArg) {
    // Если передан полный путь — берем как есть, если только имя файла — подставляем папку из конфига
    if (saveArg.includes('/') || saveArg.includes('\\')) {
      savePathToUse = saveArg
    } else {
      // Подставляем имя файла к базовой папке сейвов
      const savesDir = factorioConfig.savePath.substring(0, Math.max(factorioConfig.savePath.lastIndexOf('/'), factorioConfig.savePath.lastIndexOf('\\')))
      savePathToUse = savesDir ? `${savesDir}/${saveArg}` : saveArg
    }
  }

  const args = [
    '--start-server',
    savePathToUse,
    '--rcon-password',
    factorioConfig.rconPassword,
    '--rcon-port',
    factorioConfig.rconPort.toString(),
  ]

  if (factorioConfig.serverSettingsPath) {
    args.push('--server-settings', factorioConfig.serverSettingsPath)
  }

  if (arch() === 'arm64') {
    args.unshift(factorioConfig.path)
    factorioInst = execa('/bin/box64', args, {
      stdout: ['pipe'],
    })
  }
  else {
    factorioInst = execa(factorioConfig.path, args, {
      stdout: ['pipe'],
    })
  }

  factorioInst.on('exit', (code, signal) => {
    logger.log(`Factorio exited with code ${code} and signal ${signal}`)
    wsServer.close()
    process.exit(0)
  })

  process.on('SIGTERM', () => {
    logger.log('SIGTERM received, shutting down...')
    wsServer.close()
    factorioInst?.kill()
    process.exit(0)
  })

  for await (const line of factorioInst.iterable()) {
    gameLogger.withContext('game').log(line)

    wsServer.clients.forEach((client) => {
      client.send(line)
    })
  }
}

main().catch((e: Error) => {
  logger.error(e.message)
  logger.error(e.stack)
})
