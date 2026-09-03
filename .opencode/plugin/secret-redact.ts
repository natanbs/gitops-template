import type { Plugin } from "@opencode-ai/plugin"

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

export default (async () => {
  return {
    "tool.execute.after": async (input: any, output: any) => {
      if (output?.output) {
        output.output = scanAndRedact(output.output)
      }
    },
    "experimental.chat.messages.transform": async (input: any, output: any) => {
      if (output?.messages) {
        for (const msg of output.messages) {
          if (msg.content && typeof msg.content === "string") {
            msg.content = redactSecrets(msg.content)
          } else if (Array.isArray(msg.content)) {
            for (const part of msg.content) {
              if (part.type === "text" && typeof part.text === "string") {
                part.text = redactSecrets(part.text)
              }
            }
          }
        }
      }
    },
  }
}) satisfies Plugin
