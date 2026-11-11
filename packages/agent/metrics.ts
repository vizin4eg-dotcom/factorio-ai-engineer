import process from 'node:process'

interface TokenStats {
  promptTokens: number
  completionTokens: number
  totalTokens: number
  requestsCount: number
  lastRequestTokens: number
}

export type UsageLike = Record<string, number | undefined>

class TokenTracker {
  private stats: TokenStats = {
    promptTokens: 0,
    completionTokens: 0,
    totalTokens: 0,
    requestsCount: 0,
    lastRequestTokens: 0,
  }

  // Вызываем после каждого ответа модели
  recordUsage(usage?: UsageLike) {
    if (!usage) {
      return
    }

    const prompt = usage.prompt_tokens ?? usage.promptTokens ?? usage.promptTokenCount ?? 0
    const completion = usage.completion_tokens ?? usage.completionTokens ?? usage.candidatesTokenCount ?? 0
    const total = usage.total_tokens ?? (prompt + completion)

    this.stats.promptTokens += prompt
    this.stats.completionTokens += completion
    this.stats.totalTokens += total
    this.stats.requestsCount += 1
    this.stats.lastRequestTokens = total

    this.renderConsoleStats()
  }

  // Красивый компактный вывод в терминал
  private renderConsoleStats() {
    const time = new Date().toLocaleTimeString()
    const { requestsCount, promptTokens, completionTokens, totalTokens, lastRequestTokens } = this.stats

    // ANSI цвета: голубой, зелёный, жёлтый, сброс
    const cyan = '\u001B[36m'
    const green = '\u001B[32m'
    const yellow = '\u001B[33m'
    const gray = '\u001B[90m'
    const reset = '\u001B[0m'

    const logLine = `${gray}[${time}]${reset} ${cyan}[LLM Metrics]${reset} Req: ${yellow}#${requestsCount}${reset} | In: ${promptTokens.toLocaleString()} | Out: ${completionTokens.toLocaleString()} | Total: ${green}${totalTokens.toLocaleString()}${reset} ${gray}(Last: ${lastRequestTokens})${reset}`

    process.stdout.write(`${logLine}\n`)
  }

  getStats(): TokenStats {
    return { ...this.stats }
  }
}

export const tokenTracker = new TokenTracker()
