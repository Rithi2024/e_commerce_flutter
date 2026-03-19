export type RequestContext = {
  requestId: string;
  scope: string;
  startedAtMs: number;
  method: string;
  path: string;
  clientIp?: string;
  hasAuthorizationHeader: boolean;
  userAgent?: string;
};

const MAX_STRING_LENGTH = 160;
const MAX_ARRAY_ITEMS = 5;
const MAX_OBJECT_KEYS = 20;

export function truncate(value: unknown, maxLength = MAX_STRING_LENGTH): string {
  const text = String(value ?? "");
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 3)}...`;
}

function extractClientIp(req: Request): string | undefined {
  const forwardedFor = req.headers.get("x-forwarded-for") ?? "";
  const firstForwarded = forwardedFor
    .split(",")
    .map((value) => value.trim())
    .find(Boolean);
  return firstForwarded || undefined;
}

export function maskEmail(value: unknown): string {
  const text = String(value ?? "").trim().toLowerCase();
  const atIndex = text.indexOf("@");
  if (atIndex <= 0 || atIndex === text.length - 1) {
    return truncate(text, 40);
  }
  const local = text.slice(0, atIndex);
  const domain = text.slice(atIndex + 1);
  const visibleLocal = local.length <= 2
    ? `${local[0] || "*"}*`
    : `${local.slice(0, 2)}***`;
  return `${visibleLocal}@${domain}`;
}

export function maskPhone(value: unknown): string {
  const text = String(value ?? "").trim();
  if (text.length <= 4) return "***";
  return `${"*".repeat(Math.max(text.length - 4, 3))}${text.slice(-4)}`;
}

function isSensitiveKey(key: string): boolean {
  return /(authorization|api[_-]?key|apikey|token|secret|password|hash)/i.test(
    key,
  );
}

function isEmailKey(key: string): boolean {
  return /email/i.test(key);
}

function isPhoneKey(key: string): boolean {
  return /(phone|mobile|tel)/i.test(key);
}

export function sanitizeValue(value: unknown, key = ""): unknown {
  if (value === null || value === undefined) return value;

  if (typeof value === "string") {
    if (isSensitiveKey(key)) return "[REDACTED]";
    if (isEmailKey(key)) return maskEmail(value);
    if (isPhoneKey(key)) return maskPhone(value);
    return truncate(value);
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }

  if (Array.isArray(value)) {
    return {
      type: "array",
      length: value.length,
      sample: value.slice(0, MAX_ARRAY_ITEMS).map((item) => sanitizeValue(item, key)),
    };
  }

  if (typeof value === "object") {
    const entries = Object.entries(value).slice(0, MAX_OBJECT_KEYS);
    const sanitized: Record<string, unknown> = {};
    for (const [entryKey, entryValue] of entries) {
      sanitized[entryKey] = sanitizeValue(entryValue, entryKey);
    }
    const totalKeys = Object.keys(value as Record<string, unknown>).length;
    if (totalKeys > MAX_OBJECT_KEYS) {
      sanitized.__truncated_keys__ = totalKeys - MAX_OBJECT_KEYS;
    }
    return sanitized;
  }

  return truncate(value);
}

export function safeError(error: unknown): Record<string, unknown> {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: truncate(error.stack ?? "", 500),
    };
  }
  return { message: truncate(error) };
}

export function createRequestContext(req: Request, scope: string): RequestContext {
  return {
    requestId: crypto.randomUUID(),
    scope,
    startedAtMs: Date.now(),
    method: req.method,
    path: new URL(req.url).pathname,
    clientIp: extractClientIp(req),
    hasAuthorizationHeader: req.headers.has("authorization"),
    userAgent: truncate(req.headers.get("user-agent") ?? "", 120),
  };
}

export function durationMs(context: RequestContext): number {
  return Date.now() - context.startedAtMs;
}

function writeLog(
  level: "info" | "warning" | "error",
  event: string,
  fields: Record<string, unknown> = {},
): void {
  const payload = {
    timestamp: new Date().toISOString(),
    level,
    event,
    ...fields,
  };
  const serialized = JSON.stringify(payload);
  if (level === "error") {
    console.error(serialized);
    return;
  }
  if (level === "warning") {
    console.warn(serialized);
    return;
  }
  console.log(serialized);
}

export function logInfo(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  writeLog("info", event, fields);
}

export function logWarning(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  writeLog("warning", event, fields);
}

export function logError(
  event: string,
  fields: Record<string, unknown> = {},
): void {
  writeLog("error", event, fields);
}
