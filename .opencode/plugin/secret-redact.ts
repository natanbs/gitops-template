import { Plugin } from "@opencode/plugin"

const SECRET_PATTERNS: Array<{ name: string; pattern: RegExp }> = [
  { name: "AWS_SECRET_KEY", pattern: /(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])/g },
  { name: "AWS_ACCESS_KEY", pattern: /AKIA[0-9A-Z]{16}/g },
  { name: "GCP_SA_KEY", pattern: /-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----/g },
  { name: "GITHUB_TOKEN", pattern: /ghp_[A-Za-z0-9]{36}/g },
  { name: "GITHUB_OAUTH", pattern: /gho_[A-Za-z0-9]{36}/g },
  { name: "GITHUB_APP_TOKEN", pattern: /(?:ghu|ghs)_[A-Za-z0-9]{36}/g },
  { name: "GITLAB_TOKEN", pattern: /glpat-[A-Za-z0-9\-_]{20,}/g },
  { name: "SLACK_TOKEN", pattern: /xox[baprs]-[0-9a-zA-Z\-]{10,}/g },
  { name: "SLACK_WEBHOOK", pattern: /https:\/\/hooks\.slack\.com\/services\/T[A-Z0-9]+\/B[A-Z0-9]+\/[A-Za-z0-9]+/g },
  { name: "STRIPE_KEY", pattern: /(?:sk|pk)_(?:live|test)_[0-9a-zA-Z]{24,}/g },
  { name: "HEROKU_API_KEY", pattern: /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/g },
  { name: "JWT", pattern: /eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g },
  { name: "GENERIC_API_KEY", pattern: /(?:(?:api[_-]?key|apikey|secret[_-]?key|secretkey|access[_-]?token|auth[_-]?token|bearer)\s*[:=]\s*["']?)([A-Za-z0-9\-_.~+/]{20,})["']?/gi },
  { name: "GENERIC_SECRET", pattern: /(?:(?:password|passwd|pwd)\s*[:=]\s*["']?)([^\s"']{8,})["']?/gi },
  { name: "PRIVATE_KEY_BLOCK", pattern: /-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/g },
  { name: "HEX_SECRET", pattern: /(?:secret|token|key|password|credential)\s*[:=]\s*["']?([0-9a-fA-F]{32,})["']?/gi },
  { name: "BASE64_SECRET", pattern: /(?:secret|token|key|password|credential)\s*[:=]\s*["']?([A-Za-z0-9+/]{40,}={0,2})["']?/gi },
]

function redactSecrets(text: string): string {
  let result = text
  for (const { name, pattern } of SECRET_PATTERNS) {
    result = result.replace(pattern, (match) => {
      if (match.length <= 8) return match
      const prefix = match.slice(0, 4)
      const suffix = match.slice(-4)
      return `${prefix}...${suffix} [REDACTED:${name}]`
    })
  }
  return result
}

function scanAndRedact(obj: any): any {
  if (typeof obj === "string") return redactSecrets(obj)
  if (Array.isArray(obj)) return obj.map(scanAndRedact)
  if (obj && typeof obj === "object") {
    const out: Record<string, any> = {}
    for (const [k, v] of Object.entries(obj)) {
      out[k] = scanAndRedact(v)
    }
    return out
  }
  return obj
}

/** Redact the `{ type, value }` union carried by a tool-result part. */
function redactToolResultValue(value: any): any {
  if (value && typeof value === "object" && "value" in value) {
    const payload = value as { value: unknown }
    if (Array.isArray(payload.value)) {
      for (const item of payload.value) {
        if (item && typeof item === "object" && typeof (item as any).text === "string") {
          ;(item as any).text = redactSecrets((item as any).text)
        }
      }
    } else {
      payload.value = scanAndRedact(payload.value)
    }
    return value
  }
  return scanAndRedact(value)
}

/** Redact a system prompt and every message part visible to a model request. */
function redactRequest(context: { system?: unknown; messages?: unknown }): void {
  if (Array.isArray(context.system)) {
    for (const part of context.system) {
      if (part && typeof part === "object" && typeof (part as any).text === "string") {
        ;(part as any).text = redactSecrets((part as any).text)
      }
    }
  }
  if (!Array.isArray(context.messages)) return
  for (const message of context.messages) {
    const content = (message as any)?.content
    if (typeof content === "string") {
      ;(message as any).content = redactSecrets(content)
      continue
    }
    if (!Array.isArray(content)) continue
    for (const part of content) {
      if (!part || typeof part !== "object") continue
      const typed = part as any
      switch (typed.type) {
        case "text":
        case "reasoning":
        case "compaction":
          if (typeof typed.text === "string") typed.text = redactSecrets(typed.text)
          break
        case "tool-call":
          if (typed.input && typeof typed.input === "object") typed.input = scanAndRedact(typed.input)
          break
        case "tool-result":
          typed.result = redactToolResultValue(typed.result)
          break
      }
    }
  }
}

export default Plugin.define({
  id: "secret-redact",

  async setup(ctx) {
    // V1 `tool.execute.after` -> V2 `tool.hook("execute.after")`.
    await ctx.tool.hook("execute.after", (event: any) => {
      if (event.status === "completed") {
        const result = event.result
        if (!result) return
        if (typeof result.content === "string") {
          result.content = redactSecrets(result.content)
        } else if (Array.isArray(result.content)) {
          for (const item of result.content) {
            if (item && typeof item === "object" && typeof item.text === "string") {
              item.text = redactSecrets(item.text)
            }
          }
        }
        if (typeof result.output === "string") {
          result.output = redactSecrets(result.output)
        } else if (result.output && typeof result.output === "object") {
          result.output = scanAndRedact(result.output)
        }
        if (result.metadata && typeof result.metadata === "object") {
          result.metadata = scanAndRedact(result.metadata)
        }
      } else {
        const failure = event.error
        if (!failure) return
        if (typeof failure.message === "string") failure.message = redactSecrets(failure.message)
        if (failure.metadata && typeof failure.metadata === "object") {
          failure.metadata = scanAndRedact(failure.metadata)
        }
      }
    })

    // V1 `experimental.chat.messages.transform` -> V2 session request hooks.
    // Register on every model-request kind so no request escapes redaction.
    for (const kind of ["context", "compaction", "generate", "title"] as const) {
      await ctx.session.hook(kind, (event: any) => {
        redactRequest(event as { system?: unknown; messages?: unknown })
      })
    }
  },
})
