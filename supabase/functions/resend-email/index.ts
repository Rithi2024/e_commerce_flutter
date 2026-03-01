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
}): Promise<{ ok: boolean; id?: string; error?: string }> {
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
    return { ok: false, error };
  }

  return {
    ok: true,
    id: asString(data["id"]),
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

runtimeDeno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const resendApiKey = asString(runtimeDeno.env.get("RESEND_API_KEY"));
  const fromEmail = asString(runtimeDeno.env.get("RESEND_FROM_EMAIL"));
  const brandName = asString(runtimeDeno.env.get("APP_BRAND_NAME")) ||
    "Marketflow";

  if (resendApiKey.length === 0 || fromEmail.length === 0) {
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
  } catch (_) {
    return jsonResponse(400, { error: "Invalid JSON body" });
  }

  const operation = asString(body["operation"]).toLowerCase() ||
    "send_signup_confirmation";
  if (operation !== "send_signup_confirmation") {
    return jsonResponse(400, {
      error: "Unsupported operation. Use send_signup_confirmation",
    });
  }

  const email = asString(body["email"]).toLowerCase();
  const fullName = asString(body["full_name"]);
  const promoOptIn = asBool(body["promo_opt_in"]);
  if (!isLikelyEmail(email)) {
    return jsonResponse(400, { error: "Valid email is required" });
  }

  const confirmation = await sendResendEmail({
    apiKey: resendApiKey,
    from: fromEmail,
    to: email,
    subject: `${brandName} account confirmation`,
    html: buildConfirmationHtml({ brandName, fullName }),
  });
  if (!confirmation.ok) {
    return jsonResponse(502, {
      error: "Failed to send confirmation email",
      message: confirmation.error ?? "unknown",
    });
  }

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
    }
  }

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
