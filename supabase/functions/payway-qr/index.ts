type JsonObject = Record<string, unknown>;

const runtimeDeno = (globalThis as unknown as {
  Deno?: {
    env: { get(name: string): string | undefined };
    serve: (
      handler: (req: Request) => Response | Promise<Response>,
    ) => void;
  };
}).Deno;

if (!runtimeDeno) {
  throw new Error("Deno runtime is required");
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(
  status: number,
  body: JsonObject,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      ...extraHeaders,
      "Content-Type": "application/json",
    },
  });
}

function asString(value: unknown): string {
  if (value == null) return "";
  return String(value).trim();
}

function asNumber(value: unknown): number {
  if (typeof value === "number") return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function asInt(value: unknown, fallback: number): number {
  const parsed = Number.parseInt(asString(value), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function formatUtcReqTime(date = new Date()): string {
  const two = (v: number) => String(v).padStart(2, "0");
  return [
    date.getUTCFullYear(),
    two(date.getUTCMonth() + 1),
    two(date.getUTCDate()),
    two(date.getUTCHours()),
    two(date.getUTCMinutes()),
    two(date.getUTCSeconds()),
  ].join("");
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function utf8ToBase64(value: string): string {
  return bytesToBase64(new TextEncoder().encode(value));
}

function isLikelyBase64(value: string): boolean {
  if (value.length === 0 || value.length % 4 !== 0) return false;
  return /^[A-Za-z0-9+/]+={0,2}$/.test(value);
}

function toBase64OrKeep(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) return "";
  if (isLikelyBase64(trimmed)) return trimmed;
  return utf8ToBase64(trimmed);
}

function jsonToBase64(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "string") {
    return toBase64OrKeep(value);
  }
  return utf8ToBase64(JSON.stringify(value));
}

async function hmacSha512Base64(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    new TextEncoder().encode(message),
  );
  return bytesToBase64(new Uint8Array(signature));
}

function formatAmountForHash(amount: number): string {
  return amount.toFixed(2);
}

function asObject(value: unknown): JsonObject {
  if (value && typeof value === "object") {
    return value as JsonObject;
  }
  return {};
}

function payWayStatusCode(data: JsonObject): string {
  const status = asObject(data["status"]);
  return asString(status["code"]);
}

function payWayStatusMessage(data: JsonObject): string {
  const status = asObject(data["status"]);
  return asString(status["message"]).toLowerCase();
}

function isWrongHashResponse(data: JsonObject): boolean {
  const code = payWayStatusCode(data);
  if (code === "1" || code === "5") return true;
  return payWayStatusMessage(data).includes("wrong hash") ||
    payWayStatusMessage(data).includes("invalid hash");
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const trimmed = value.trim();
    if (trimmed.length === 0 || seen.has(trimmed)) continue;
    seen.add(trimmed);
    result.push(trimmed);
  }
  return result;
}

async function postPayWay(
  url: string,
  payload: JsonObject,
): Promise<{ status: number; data: JsonObject }> {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  let data: JsonObject = {};
  try {
    const raw = await response.json();
    if (raw && typeof raw === "object") {
      data = raw as JsonObject;
    }
  } catch (_) {
    data = {};
  }

  return { status: response.status, data };
}

async function handleGenerateQr(
  body: JsonObject,
  merchantId: string,
  apiKey: string,
  baseUrl: string,
): Promise<Response> {
  const tranId = asString(body["tran_id"]);
  const amount = asNumber(body["amount"]);
  if (tranId.length === 0) {
    return jsonResponse(400, { error: "tran_id is required" });
  }
  if (tranId.length > 20) {
    return jsonResponse(400, { error: "tran_id must be 20 characters or less" });
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    return jsonResponse(400, { error: "amount must be a valid positive number" });
  }

  const currency = asString(body["currency"]).toUpperCase() || "USD";
  const purchaseType = asString(body["purchase_type"]).toLowerCase() ||
    "purchase";
  const paymentOption = asString(body["payment_option"]).toLowerCase() ||
    "abapay_khqr";
  const firstName = asString(body["first_name"]);
  const lastName = asString(body["last_name"]);
  const email = asString(body["email"]);
  const phone = asString(body["phone"]);
  const lifetime = Math.min(Math.max(asInt(body["lifetime"], 15), 3), 43200);
  const qrImageTemplate = asString(body["qr_image_template"]) ||
    "template3_color";

  const items = jsonToBase64(body["items"]);
  const callbackSource = asString(body["callback_url"]);
  const callbackUrl = toBase64OrKeep(callbackSource);
  const returnDeeplink = jsonToBase64(body["return_deeplink"]);
  const customFields = jsonToBase64(body["custom_fields"]);
  const returnParams = jsonToBase64(body["return_params"]);
  const payout = jsonToBase64(body["payout"]);

  const reqTime = formatUtcReqTime();
  const normalizedAmount = Number(formatAmountForHash(amount));
  const payloadBase: JsonObject = {
    req_time: reqTime,
    merchant_id: merchantId,
    tran_id: tranId,
    amount: normalizedAmount,
    currency,
    purchase_type: purchaseType,
    payment_option: paymentOption,
    lifetime,
    qr_image_template: qrImageTemplate,
  };
  if (firstName.length > 0) payloadBase["first_name"] = firstName;
  if (lastName.length > 0) payloadBase["last_name"] = lastName;
  if (email.length > 0) payloadBase["email"] = email;
  if (phone.length > 0) payloadBase["phone"] = phone;
  if (items.length > 0) payloadBase["items"] = items;
  if (callbackUrl.length > 0) payloadBase["callback_url"] = callbackUrl;
  if (returnDeeplink.length > 0) payloadBase["return_deeplink"] = returnDeeplink;
  if (customFields.length > 0) payloadBase["custom_fields"] = customFields;
  if (returnParams.length > 0) payloadBase["return_params"] = returnParams;
  if (payout.length > 0) payloadBase["payout"] = payout;

  const amountHashCandidates = uniqueStrings([
    normalizedAmount.toString(),
    formatAmountForHash(normalizedAmount),
    amount.toString(),
    formatAmountForHash(amount),
  ]);

  let finalStatus = 500;
  let finalData: JsonObject = {
    status: {
      code: "500",
      message: "No response from PayWay",
    },
  };

  for (const amountForHash of amountHashCandidates) {
    const hashInput = reqTime + merchantId + tranId + amountForHash + items +
      firstName + lastName + email + phone + purchaseType + paymentOption +
      callbackUrl + returnDeeplink + currency + customFields + returnParams +
      payout + lifetime.toString() + qrImageTemplate;
    const hash = await hmacSha512Base64(apiKey, hashInput);
    const payload: JsonObject = { ...payloadBase, hash };
    const { status, data } = await postPayWay(
      `${baseUrl}/api/payment-gateway/v1/payments/generate-qr`,
      payload,
    );
    finalStatus = status;
    finalData = data;

    if (!isWrongHashResponse(data)) {
      break;
    }
  }

  return jsonResponse(finalStatus, {
    operation: "generate_qr",
    tran_id: tranId,
    ...finalData,
  });
}

async function handleCheckTransaction(
  body: JsonObject,
  merchantId: string,
  apiKey: string,
  baseUrl: string,
): Promise<Response> {
  const tranId = asString(body["tran_id"]);
  if (tranId.length === 0) {
    return jsonResponse(400, { error: "tran_id is required" });
  }
  if (tranId.length > 20) {
    return jsonResponse(400, { error: "tran_id must be 20 characters or less" });
  }

  const reqTime = formatUtcReqTime();
  const hashInput = reqTime + merchantId + tranId;
  const hash = await hmacSha512Base64(apiKey, hashInput);

  const payload: JsonObject = {
    req_time: reqTime,
    merchant_id: merchantId,
    tran_id: tranId,
    hash,
  };

  const { status, data } = await postPayWay(
    `${baseUrl}/api/payment-gateway/v1/payments/check-transaction-2`,
    payload,
  );

  return jsonResponse(status, {
    operation: "check_transaction",
    tran_id: tranId,
    ...data,
  });
}

runtimeDeno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const merchantId = asString(runtimeDeno.env.get("PAYWAY_MERCHANT_ID"));
  const apiKey = asString(runtimeDeno.env.get("PAYWAY_API_KEY"));
  const baseUrl = (
    asString(runtimeDeno.env.get("PAYWAY_BASE_URL")) ||
    "https://checkout-sandbox.payway.com.kh"
  ).replace(/\/+$/, "");
  if (merchantId.length === 0 || apiKey.length === 0) {
    return jsonResponse(500, {
      error:
        "Missing PAYWAY_MERCHANT_ID or PAYWAY_API_KEY in Edge Function secrets",
    });
  }

  let body: JsonObject = {};
  try {
    const raw = await req.json();
    if (raw && typeof raw === "object") {
      body = raw as JsonObject;
    }
  } catch (_) {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const operation = asString(body["operation"]).toLowerCase() || "generate_qr";
  try {
    if (operation === "generate_qr") {
      return await handleGenerateQr(body, merchantId, apiKey, baseUrl);
    }
    if (operation === "check_transaction") {
      return await handleCheckTransaction(body, merchantId, apiKey, baseUrl);
    }

    return jsonResponse(400, {
      error: "Unsupported operation. Use generate_qr or check_transaction",
    });
  } catch (error) {
    return jsonResponse(500, {
      error: "Unexpected server error",
      message: error instanceof Error ? error.message : "unknown",
    });
  }
});
