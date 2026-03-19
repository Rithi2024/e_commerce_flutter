const MAX_STRING_LENGTH = 160;
const MAX_ARRAY_ITEMS = 5;
const MAX_OBJECT_KEYS = 20;

function truncate(value, maxLength = MAX_STRING_LENGTH) {
  const text = String(value ?? '');
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 3)}...`;
}

function generateRequestId(prefix = 'req') {
  const randomPart = Math.random().toString(36).slice(2, 10);
  return `${prefix}_${Date.now().toString(36)}_${randomPart}`;
}

function extractClientIp(req) {
  const forwardedFor =
    typeof req.headers['x-forwarded-for'] === 'string'
      ? req.headers['x-forwarded-for']
      : '';
  const firstForwarded = forwardedFor
    .split(',')
    .map((value) => value.trim())
    .find(Boolean);
  return firstForwarded || undefined;
}

function maskEmail(value) {
  const text = String(value ?? '').trim().toLowerCase();
  const atIndex = text.indexOf('@');
  if (atIndex <= 0 || atIndex === text.length - 1) {
    return truncate(text, 40);
  }
  const local = text.slice(0, atIndex);
  const domain = text.slice(atIndex + 1);
  const visibleLocal = local.length <= 2
    ? `${local[0] || '*'}*`
    : `${local.slice(0, 2)}***`;
  return `${visibleLocal}@${domain}`;
}

function maskPhone(value) {
  const text = String(value ?? '').trim();
  if (text.length <= 4) return '***';
  return `${'*'.repeat(Math.max(text.length - 4, 3))}${text.slice(-4)}`;
}

function isSensitiveKey(key) {
  return /(authorization|api[_-]?key|apikey|token|secret|password|hash)/i.test(
    key || '',
  );
}

function isEmailKey(key) {
  return /email/i.test(key || '');
}

function isPhoneKey(key) {
  return /(phone|mobile|tel)/i.test(key || '');
}

function sanitizeValue(value, key = '') {
  if (value === null || value === undefined) return value;

  if (typeof value === 'string') {
    if (isSensitiveKey(key)) return '[REDACTED]';
    if (isEmailKey(key)) return maskEmail(value);
    if (isPhoneKey(key)) return maskPhone(value);
    return truncate(value);
  }

  if (typeof value === 'number' || typeof value === 'boolean') {
    return value;
  }

  if (Array.isArray(value)) {
    return {
      type: 'array',
      length: value.length,
      sample: value
        .slice(0, MAX_ARRAY_ITEMS)
        .map((item) => sanitizeValue(item, key)),
    };
  }

  if (typeof value === 'object') {
    const entries = Object.entries(value).slice(0, MAX_OBJECT_KEYS);
    const sanitized = {};
    for (const [entryKey, entryValue] of entries) {
      sanitized[entryKey] = sanitizeValue(entryValue, entryKey);
    }
    const totalKeys = Object.keys(value).length;
    if (totalKeys > MAX_OBJECT_KEYS) {
      sanitized.__truncated_keys__ = totalKeys - MAX_OBJECT_KEYS;
    }
    return sanitized;
  }

  return truncate(value);
}

function listObjectKeys(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return [];
  }
  return Object.keys(value).sort();
}

function safeError(error) {
  if (error instanceof Error) {
    return {
      name: error.name,
      message: error.message,
      stack: truncate(error.stack || '', 500),
    };
  }
  return { message: truncate(error) };
}

function createRequestContext(req, scope) {
  const requestId = generateRequestId(scope.replace(/[^a-z0-9]+/gi, '_'));
  return {
    requestId,
    scope,
    startedAtMs: Date.now(),
    method: req.method,
    path: typeof req.url === 'string' ? req.url : '',
    clientIp: extractClientIp(req),
    hasAuthorizationHeader:
      typeof req.headers.authorization === 'string' &&
      req.headers.authorization.trim().length > 0,
    userAgent: truncate(req.headers['user-agent'] || '', 120),
  };
}

function durationMs(context) {
  return Date.now() - context.startedAtMs;
}

function log(level, event, fields = {}) {
  const payload = {
    timestamp: new Date().toISOString(),
    level,
    event,
    ...fields,
  };
  const serialized = JSON.stringify(payload);
  if (level === 'error') {
    console.error(serialized);
    return;
  }
  if (level === 'warning') {
    console.warn(serialized);
    return;
  }
  console.log(serialized);
}

function logInfo(event, fields = {}) {
  log('info', event, fields);
}

function logWarning(event, fields = {}) {
  log('warning', event, fields);
}

function logError(event, fields = {}) {
  log('error', event, fields);
}

module.exports = {
  createRequestContext,
  durationMs,
  listObjectKeys,
  logError,
  logInfo,
  logWarning,
  safeError,
  sanitizeValue,
  truncate,
};
