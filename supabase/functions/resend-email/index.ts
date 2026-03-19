import {
  createRequestContext,
  durationMs,
  logError,
  logInfo,
  logWarning,
  maskEmail,
  safeError,
} from "../_shared/logging.ts";

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

function asBool(value: unknown): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value !== 0;
  const raw = asString(value).toLowerCase();
  return raw === "true" || raw === "1" || raw === "yes";
}

function asNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number.parseFloat(asString(value));
  return Number.isFinite(parsed) ? parsed : 0;
}

function isLikelyEmail(value: string): boolean {
  if (value.length < 5) return false;
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function titleCaseStatus(value: string): string {
  const normalized = asString(value).replaceAll(/[_-]+/g, " ");
  if (normalized.length === 0) return "Pending";
  return normalized
    .split(/\s+/)
    .filter((part) => part.length > 0)
    .map((part) => `${part[0].toUpperCase()}${part.slice(1).toLowerCase()}`)
    .join(" ");
}

function formatMoney(amount: number): string {
  return asNumber(amount).toFixed(2);
}

async function sendResendEmail({
  apiKey,
  from,
  to,
  subject,
  html,
}: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  html: string;
}): Promise<{ ok: boolean; id?: string; error?: string; statusCode: number }> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      html,
    }),
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

  if (!response.ok) {
    const error = asString(data["message"]) || `HTTP ${response.status}`;
    return { ok: false, error, statusCode: response.status };
  }

  return {
    ok: true,
    id: asString(data["id"]),
    statusCode: response.status,
  };
}

function buildConfirmationHtml({
  brandName,
  fullName,
}: {
  brandName: string;
  fullName: string;
}): string {
  const safeBrand = escapeHtml(brandName);
  const safeName = escapeHtml(fullName);
  const greeting = safeName.length === 0 ? "Hello," : `Hello ${safeName},`;

  return `
    <div style="font-family:Arial,sans-serif;line-height:1.5;color:#1d1d1f;">
      <h2 style="margin:0 0 12px;">Welcome to ${safeBrand}</h2>
      <p style="margin:0 0 10px;">${greeting}</p>
      <p style="margin:0 0 10px;">
        Your account has been created successfully. Thanks for registering with ${safeBrand}.
      </p>
      <p style="margin:0 0 10px;">
        If this wasn't you, please contact support immediately.
      </p>
      <p style="margin:20px 0 0;color:#6b7280;font-size:12px;">
        This is an automated message.
      </p>
    </div>
  `;
}

function buildPromotionOptInHtml({
  brandName,
  fullName,
}: {
  brandName: string;
  fullName: string;
}): string {
  const safeBrand = escapeHtml(brandName);
  const safeName = escapeHtml(fullName);
  const greeting = safeName.length === 0 ? "Hello," : `Hello ${safeName},`;

  return `
    <div style="font-family:Arial,sans-serif;line-height:1.5;color:#1d1d1f;">
      <h2 style="margin:0 0 12px;">${safeBrand} Promotions Subscription</h2>
      <p style="margin:0 0 10px;">${greeting}</p>
      <p style="margin:0 0 10px;">
        You're now subscribed to promotional emails from ${safeBrand}.
      </p>
      <p style="margin:0 0 10px;">
        We'll send updates about new products, limited offers, and special campaigns.
      </p>
      <p style="margin:20px 0 0;color:#6b7280;font-size:12px;">
        You can change this preference from your profile at any time.
      </p>
    </div>
  `;
}

function buildOrderItemsHtml(items: unknown): string {
  if (!Array.isArray(items) || items.length === 0) {
    return `
      <li style="margin:0 0 8px;color:#4b5563;">
        Your order items are available in your account history.
      </li>
    `;
  }

  return items
    .map((item) => {
      const record = item && typeof item === "object"
        ? item as JsonObject
        : {} as JsonObject;
      const name = escapeHtml(asString(record["name"]) || "Item");
      const qty = Math.max(1, Math.trunc(asNumber(record["qty"])) || 1);
      const price = formatMoney(asNumber(record["price"]));
      const size = escapeHtml(asString(record["size"]));
      const color = escapeHtml(asString(record["color"]));
      const details = [size && `Size: ${size}`, color && `Color: ${color}`]
        .filter(Boolean)
        .join(" | ");
      const detailsHtml = details.length === 0
        ? ""
        : `<div style="font-size:12px;color:#6b7280;margin-top:4px;">${details}</div>`;
      return `
        <li style="margin:0 0 10px;color:#111827;">
          <span>${name} x${qty} - $${price}</span>
          ${detailsHtml}
        </li>
      `;
    })
    .join("");
}

function buildOrderConfirmationHtml({
  brandName,
  userName,
  orderId,
  total,
  status,
  itemsHtml,
}: {
  brandName: string;
  userName: string;
  orderId: string;
  total: string;
  status: string;
  itemsHtml: string;
}): string {
  const safeBrand = escapeHtml(brandName);
  const safeName = escapeHtml(userName) || "there";
  const safeOrderId = escapeHtml(orderId);
  const safeTotal = escapeHtml(total);
  const safeStatus = escapeHtml(status);
  const currentYear = new Date().getUTCFullYear();

  return `
    <div style="font-family:Arial,sans-serif;background:#f6f9fc;padding:20px;">
      <div style="max-width:500px;margin:auto;background:#ffffff;padding:30px;border-radius:10px;">
        <h2 style="color:#333333;margin:0 0 18px;">Order Confirmation</h2>
        <p style="margin:0 0 12px;">Hi ${safeName},</p>
        <p style="margin:0 0 18px;">Thank you for your order.</p>
        <h3 style="margin:0 0 12px;">Order Details</h3>
        <p style="margin:0 0 8px;"><strong>Order ID:</strong> ${safeOrderId}</p>
        <p style="margin:0 0 8px;"><strong>Total:</strong> $${safeTotal}</p>
        <p style="margin:0 0 18px;"><strong>Status:</strong> ${safeStatus}</p>
        <h3 style="margin:0 0 12px;">Items</h3>
        <ul style="padding-left:18px;margin:0 0 18px;">
          ${itemsHtml}
        </ul>
        <p style="margin:0 0 18px;">We'll notify you when your order is shipped.</p>
        <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;">
        <p style="font-size:12px;color:#888888;margin:0;">&copy; ${currentYear} ${safeBrand}</p>
      </div>
    </div>
  `;
}

runtimeDeno.serve(async (req: Request): Promise<Response> => {
  const context = createRequestContext(req, "resend_email");
  if (req.method === "OPTIONS") {
    logInfo("resend.request_preflight", {
      requestId: context.requestId,
      durationMs: durationMs(context),
    });
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    logWarning("resend.method_not_allowed", {
      requestId: context.requestId,
      method: req.method,
      durationMs: durationMs(context),
    });
    return jsonResponse(405, { error: "Method not allowed" });
  }

  logInfo("resend.request_received", {
    requestId: context.requestId,
    scope: context.scope,
    method: context.method,
    path: context.path,
    clientIp: context.clientIp,
    hasAuthorizationHeader: context.hasAuthorizationHeader,
    userAgent: context.userAgent,
  });

  const resendApiKey = asString(runtimeDeno.env.get("RESEND_API_KEY"));
  const fromEmail = asString(runtimeDeno.env.get("RESEND_FROM_EMAIL"));
  const brandName = asString(runtimeDeno.env.get("APP_BRAND_NAME")) ||
    "MarketFlow";

  if (resendApiKey.length === 0 || fromEmail.length === 0) {
    logError("resend.missing_configuration", {
      requestId: context.requestId,
      hasApiKey: resendApiKey.length > 0,
      hasFromEmail: fromEmail.length > 0,
      durationMs: durationMs(context),
    });
    return jsonResponse(500, {
      error:
        "Missing RESEND_API_KEY or RESEND_FROM_EMAIL in Edge Function secrets",
    });
  }

  let body: JsonObject = {};
  try {
    const raw = await req.json();
    if (raw && typeof raw === "object") {
      body = raw as JsonObject;
    }
  } catch (error) {
    logWarning("resend.invalid_json_body", {
      requestId: context.requestId,
      durationMs: durationMs(context),
      error: safeError(error),
    });
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const operation = asString(body["operation"]).toLowerCase() ||
    "send_signup_confirmation";
  logInfo("resend.operation_resolved", {
    requestId: context.requestId,
    operation,
  });
  if (
    operation !== "send_signup_confirmation" &&
    operation !== "send_order_confirmation"
  ) {
    logWarning("resend.unsupported_operation", {
      requestId: context.requestId,
      operation,
      durationMs: durationMs(context),
    });
    return jsonResponse(400, {
      error:
        "Unsupported operation. Use send_signup_confirmation or send_order_confirmation",
    });
  }

  const email = asString(body["email"]).toLowerCase();
  if (!isLikelyEmail(email)) {
    logWarning("resend.invalid_email", {
      requestId: context.requestId,
      email: email.length > 0 ? maskEmail(email) : undefined,
      durationMs: durationMs(context),
    });
    return jsonResponse(400, { error: "Valid email is required" });
  }

  if (operation === "send_order_confirmation") {
    const userName = asString(body["user_name"]) || asString(body["full_name"]);
    const orderId = asString(body["order_id"]);
    const total = formatMoney(asNumber(body["total"]));
    const status = titleCaseStatus(asString(body["status"]));
    const items = Array.isArray(body["items"]) ? body["items"] : [];

    logInfo("resend.order_confirmation_payload_parsed", {
      requestId: context.requestId,
      email: maskEmail(email),
      userNameProvided: userName.length > 0,
      orderId,
      itemCount: items.length,
      total,
      status,
    });

    if (orderId.length === 0) {
      return jsonResponse(400, { error: "Order ID is required" });
    }

    const confirmation = await sendResendEmail({
      apiKey: resendApiKey,
      from: fromEmail,
      to: email,
      subject: `${brandName} order confirmation #${orderId}`,
      html: buildOrderConfirmationHtml({
        brandName,
        userName,
        orderId,
        total,
        status,
        itemsHtml: buildOrderItemsHtml(items),
      }),
    });
    if (!confirmation.ok) {
      logError("resend.order_confirmation_failed", {
        requestId: context.requestId,
        email: maskEmail(email),
        orderId,
        statusCode: confirmation.statusCode,
        error: confirmation.error ?? "unknown",
        durationMs: durationMs(context),
      });
      return jsonResponse(502, {
        error: "Failed to send order confirmation email",
        message: confirmation.error ?? "unknown",
      });
    }

    logInfo("resend.order_confirmation_sent", {
      requestId: context.requestId,
      email: maskEmail(email),
      orderId,
      statusCode: confirmation.statusCode,
      resendId: confirmation.id || undefined,
      durationMs: durationMs(context),
    });

    return jsonResponse(200, {
      ok: true,
      operation,
      email,
      order_confirmation_sent: true,
      order_id: orderId,
    });
  }

  const fullName = asString(body["full_name"]);
  const promoOptIn = asBool(body["promo_opt_in"]);
  logInfo("resend.request_payload_parsed", {
    requestId: context.requestId,
    email: email.length > 0 ? maskEmail(email) : undefined,
    fullNameProvided: fullName.length > 0,
    promoOptIn,
  });

  const confirmation = await sendResendEmail({
    apiKey: resendApiKey,
    from: fromEmail,
    to: email,
    subject: `${brandName} account confirmation`,
    html: buildConfirmationHtml({ brandName, fullName }),
  });
  if (!confirmation.ok) {
    logError("resend.confirmation_failed", {
      requestId: context.requestId,
      email: maskEmail(email),
      statusCode: confirmation.statusCode,
      error: confirmation.error ?? "unknown",
      durationMs: durationMs(context),
    });
    return jsonResponse(502, {
      error: "Failed to send confirmation email",
      message: confirmation.error ?? "unknown",
    });
  }

  logInfo("resend.confirmation_sent", {
    requestId: context.requestId,
    email: maskEmail(email),
    statusCode: confirmation.statusCode,
    resendId: confirmation.id || undefined,
  });

  let promotionSent = false;
  let promotionError = "";
  if (promoOptIn) {
    const promotion = await sendResendEmail({
      apiKey: resendApiKey,
      from: fromEmail,
      to: email,
      subject: `${brandName} promotion subscription`,
      html: buildPromotionOptInHtml({ brandName, fullName }),
    });
    promotionSent = promotion.ok;
    if (!promotion.ok) {
      promotionError = promotion.error ?? "unknown";
      logWarning("resend.promotion_failed", {
        requestId: context.requestId,
        email: maskEmail(email),
        statusCode: promotion.statusCode,
        error: promotionError,
      });
    } else {
      logInfo("resend.promotion_sent", {
        requestId: context.requestId,
        email: maskEmail(email),
        statusCode: promotion.statusCode,
        resendId: promotion.id || undefined,
      });
    }
  } else {
    logInfo("resend.promotion_skipped", {
      requestId: context.requestId,
      email: maskEmail(email),
    });
  }

  logInfo("resend.completed", {
    requestId: context.requestId,
    email: maskEmail(email),
    confirmationSent: true,
    promotionRequested: promoOptIn,
    promotionSent,
    durationMs: durationMs(context),
  });

  return jsonResponse(200, {
    ok: true,
    operation,
    email,
    confirmation_sent: true,
    promotion_requested: promoOptIn,
    promotion_sent: promotionSent,
    promotion_error: promotionError,
  });
});
