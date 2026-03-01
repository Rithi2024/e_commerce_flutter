const DEFAULT_ALLOWED_FUNCTIONS = [
  'Payway',
  'payway',
  'payway-qr',
  'Resend-email',
  'resend-email',
  'auth-email',
  'registration-email',
];

function toJsonResponse(res, status, payload) {
  res.status(status).json(payload);
}

function parseAllowedFunctions(rawValue) {
  const value = (rawValue || '').trim();
  if (!value) {
    return new Set(DEFAULT_ALLOWED_FUNCTIONS);
  }
  return new Set(
    value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0),
  );
}

function readRequestBody(req) {
  if (typeof req.body === 'string') {
    if (req.body.trim().length === 0) return {};
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return {};
    }
  }
  if (req.body && typeof req.body === 'object') {
    return req.body;
  }
  return {};
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    toJsonResponse(res, 405, {
      code: 'METHOD_NOT_ALLOWED',
      message: 'Use POST',
    });
    return;
  }

  const supabaseUrl = (process.env.SUPABASE_URL || '').trim();
  const supabaseAnonKey = (process.env.SUPABASE_ANON_KEY || '').trim();
  const supabaseServiceRoleKey = (
    process.env.SUPABASE_SERVICE_ROLE_KEY || ''
  ).trim();
  if (!supabaseUrl || !supabaseAnonKey) {
    toJsonResponse(res, 500, {
      code: 'MISSING_SUPABASE_CONFIG',
      message: 'SUPABASE_URL and SUPABASE_ANON_KEY are required',
    });
    return;
  }

  const requestBody = readRequestBody(req);
  const functionName = String(requestBody.function || '').trim();
  if (!functionName) {
    toJsonResponse(res, 400, {
      code: 'INVALID_FUNCTION_NAME',
      message: 'function is required',
    });
    return;
  }

  const allowedFunctions = parseAllowedFunctions(
    process.env.PROXY_ALLOWED_FUNCTIONS,
  );
  if (!allowedFunctions.has(functionName)) {
    toJsonResponse(res, 403, {
      code: 'FUNCTION_NOT_ALLOWED',
      message: `Function "${functionName}" is not allowed`,
    });
    return;
  }

  const payload =
    requestBody.body && typeof requestBody.body === 'object'
      ? requestBody.body
      : {};
  const upstreamUrl = `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/${encodeURIComponent(functionName)}`;
  const authHeader =
    typeof req.headers.authorization === 'string'
      ? req.headers.authorization.trim()
      : '';
  const authorization =
    authHeader ||
    (supabaseServiceRoleKey
      ? `Bearer ${supabaseServiceRoleKey}`
      : `Bearer ${supabaseAnonKey}`);

  try {
    const upstreamResponse = await fetch(upstreamUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        apikey: supabaseAnonKey,
        Authorization: authorization,
      },
      body: JSON.stringify(payload),
    });

    const contentType =
      upstreamResponse.headers.get('content-type') ||
      'application/json; charset=utf-8';
    const rawBody = await upstreamResponse.text();

    res.status(upstreamResponse.status);
    res.setHeader('Content-Type', contentType);
    res.send(rawBody.trim().isEmpty ? '{}' : rawBody);
  } catch (error) {
    toJsonResponse(res, 502, {
      code: 'UPSTREAM_REQUEST_FAILED',
      message: error instanceof Error ? error.message : 'Unknown proxy error',
    });
  }
};
