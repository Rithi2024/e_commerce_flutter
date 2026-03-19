const DEFAULT_ALLOWED_RPCS = [
  'rpc_get_profile',
  'rpc_upsert_profile',
  'rpc_list_products',
  'rpc_get_product_variant_stocks',
  'rpc_list_best_seller_product_ids',
  'rpc_get_active_event',
  'rpc_get_wishlist_ids',
  'rpc_toggle_wishlist',
  'rpc_get_cart_items',
  'rpc_cart_total',
  'rpc_add_to_cart',
  'rpc_set_cart_qty',
  'rpc_clear_cart',
  'rpc_place_order',
  'rpc_get_orders',
  'rpc_get_order_support_statuses',
  'rpc_validate_promo_code',
  'rpc_upsert_payway_transaction',
  'rpc_app_log',
  'rpc_admin_list_profiles',
  'rpc_admin_set_account_type',
  'rpc_admin_list_orders',
  'rpc_staff_update_order_status',
  'rpc_staff_update_order_address',
  'rpc_staff_update_support_request_status',
  'rpc_staff_reply_product_rating',
  'rpc_admin_confirm_cash_payment',
  'rpc_staff_list_support_requests',
  'rpc_admin_list_events',
  'rpc_admin_create_event',
  'rpc_admin_update_event',
  'rpc_admin_delete_event',
  'rpc_admin_get_product_variant_stocks',
  'rpc_admin_set_product_variant_stocks',
  'rpc_admin_create_product',
  'rpc_admin_update_product',
  'rpc_admin_delete_product',
];
const {
  createRequestContext,
  durationMs,
  listObjectKeys,
  logError,
  logInfo,
  logWarning,
  safeError,
  sanitizeValue,
  truncate,
} = require('./_logging');

const DEFAULT_ALLOWED_TABLES = [
  'profiles',
  'events',
  'orders',
  'product_ratings',
  'payway_transactions',
];

function json(res, status, payload) {
  res.status(status).json(payload);
}

function readBody(req) {
  if (typeof req.body === 'string') {
    const value = req.body.trim();
    if (value.length === 0) return {};
    try {
      return JSON.parse(value);
    } catch (_) {
      return {};
    }
  }
  if (req.body && typeof req.body === 'object') {
    return req.body;
  }
  return {};
}

function parseAllowList(raw, defaults) {
  const value = (raw || '').trim();
  if (!value) return new Set(defaults);
  return new Set(
    value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item.length > 0),
  );
}

function encodeScalar(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  return String(value);
}

function encodeInValue(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  const text = String(value).replace(/"/g, '\\"');
  return `"${text}"`;
}

function encodeFilterExpression(op, value) {
  switch ((op || '').toString().trim().toLowerCase()) {
    case 'eq':
      return `eq.${encodeScalar(value)}`;
    case 'neq':
      return `neq.${encodeScalar(value)}`;
    case 'gt':
      return `gt.${encodeScalar(value)}`;
    case 'gte':
      return `gte.${encodeScalar(value)}`;
    case 'lt':
      return `lt.${encodeScalar(value)}`;
    case 'lte':
      return `lte.${encodeScalar(value)}`;
    case 'like':
      return `like.${encodeScalar(value)}`;
    case 'ilike':
      return `ilike.${encodeScalar(value)}`;
    case 'is':
      return `is.${encodeScalar(value)}`;
    case 'in': {
      const values = Array.isArray(value) ? value : [value];
      const encoded = values.map((item) => encodeInValue(item)).join(',');
      return `in.(${encoded})`;
    }
    default:
      return null;
  }
}

function buildOrderClause(orders) {
  if (!Array.isArray(orders) || orders.length === 0) return '';
  return orders
    .map((raw) => {
      const item = raw && typeof raw === 'object' ? raw : {};
      const column = String(item.column || '').trim();
      if (!column) return '';
      const ascending = item.ascending !== false;
      const nullsPart =
        typeof item.nullsFirst === 'boolean'
          ? item.nullsFirst
            ? '.nullsfirst'
            : '.nullslast'
          : '';
      return `${column}.${ascending ? 'asc' : 'desc'}${nullsPart}`;
    })
    .filter(Boolean)
    .join(',');
}

function summarizeFilters(filters) {
  if (!Array.isArray(filters)) return [];
  return filters.slice(0, 10).map((rawFilter) => {
    const filter =
      rawFilter && typeof rawFilter === 'object' ? rawFilter : {};
    return {
      column: String(filter.column || '').trim(),
      op: String(filter.op || '').trim().toLowerCase(),
      value: sanitizeValue(filter.value, String(filter.column || '')),
    };
  });
}

function summarizeOrders(orders) {
  if (!Array.isArray(orders)) return [];
  return orders.slice(0, 10).map((rawOrder) => {
    const order =
      rawOrder && typeof rawOrder === 'object' ? rawOrder : {};
    return {
      column: String(order.column || '').trim(),
      ascending: order.ascending !== false,
      nullsFirst:
        typeof order.nullsFirst === 'boolean' ? order.nullsFirst : undefined,
    };
  });
}

function summarizeValues(values) {
  if (Array.isArray(values)) {
    return {
      type: 'array',
      length: values.length,
      sampleKeys: values.slice(0, 3).map((item) => listObjectKeys(item)),
    };
  }
  return {
    type: values && typeof values === 'object' ? 'object' : typeof values,
    keys: listObjectKeys(values),
  };
}

async function forwardToSupabase({
  req,
  supabaseUrl,
  supabaseAnonKey,
  path,
  method,
  searchParams = null,
  body = null,
  prefer = '',
}) {
  const url = new URL(`${supabaseUrl.replace(/\/+$/, '')}${path}`);
  if (searchParams instanceof URLSearchParams) {
    searchParams.forEach((value, key) => url.searchParams.append(key, value));
  }

  const clientAuth =
    typeof req.headers.authorization === 'string'
      ? req.headers.authorization.trim()
      : '';
  const authorization = clientAuth || `Bearer ${supabaseAnonKey}`;

  const headers = {
    apikey: supabaseAnonKey,
    Authorization: authorization,
  };
  if (body !== null) {
    headers['Content-Type'] = 'application/json';
  }
  if (prefer) {
    headers['Prefer'] = prefer;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body === null ? undefined : JSON.stringify(body),
  });
  return response;
}

module.exports = async (req, res) => {
  const context = createRequestContext(req, 'supabase_data_proxy');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );

  logInfo('proxy.data.request_received', {
    requestId: context.requestId,
    scope: context.scope,
    method: context.method,
    path: context.path,
    clientIp: context.clientIp,
    hasAuthorizationHeader: context.hasAuthorizationHeader,
    userAgent: context.userAgent,
  });

  if (req.method === 'OPTIONS') {
    logInfo('proxy.data.preflight', {
      requestId: context.requestId,
      durationMs: durationMs(context),
    });
    res.status(204).end();
    return;
  }

  if (req.method !== 'POST') {
    logWarning('proxy.data.method_not_allowed', {
      requestId: context.requestId,
      method: req.method,
      durationMs: durationMs(context),
    });
    json(res, 405, {
      code: 'METHOD_NOT_ALLOWED',
      message: 'Use POST',
    });
    return;
  }

  const supabaseUrl = (process.env.SUPABASE_URL || '').trim();
  const supabaseAnonKey = (process.env.SUPABASE_ANON_KEY || '').trim();
  if (!supabaseUrl || !supabaseAnonKey) {
    logError('proxy.data.missing_supabase_config', {
      requestId: context.requestId,
      hasSupabaseUrl: supabaseUrl.length > 0,
      hasSupabaseAnonKey: supabaseAnonKey.length > 0,
      durationMs: durationMs(context),
    });
    json(res, 500, {
      code: 'MISSING_SUPABASE_CONFIG',
      message: 'SUPABASE_URL and SUPABASE_ANON_KEY are required',
    });
    return;
  }

  const allowedRpcs = parseAllowList(
    process.env.PROXY_ALLOWED_RPCS,
    DEFAULT_ALLOWED_RPCS,
  );
  const allowedTables = parseAllowList(
    process.env.PROXY_ALLOWED_TABLES,
    DEFAULT_ALLOWED_TABLES,
  );

  const body = readBody(req);
  const kind = String(body.kind || '').trim().toLowerCase();
  let operationSummary = {
    kind,
    bodyKeys: listObjectKeys(body),
  };

  let upstreamResponse;
  try {
    if (kind === 'rpc') {
      const rpc = String(body.rpc || '').trim();
      if (!rpc) {
        logWarning('proxy.data.invalid_rpc_name', {
          requestId: context.requestId,
          bodyKeys: listObjectKeys(body),
          durationMs: durationMs(context),
        });
        json(res, 400, {
          code: 'INVALID_RPC_NAME',
          message: 'rpc is required',
        });
        return;
      }
      if (!allowedRpcs.has(rpc)) {
        logWarning('proxy.data.rpc_not_allowed', {
          requestId: context.requestId,
          rpc,
          durationMs: durationMs(context),
        });
        json(res, 403, {
          code: 'RPC_NOT_ALLOWED',
          message: `RPC "${rpc}" is not allowed`,
        });
        return;
      }
      const params =
        body.params && typeof body.params === 'object' ? body.params : {};
      operationSummary = {
        kind,
        rpc,
        paramKeys: listObjectKeys(params),
      };
      logInfo('proxy.data.forwarding_rpc', {
        requestId: context.requestId,
        ...operationSummary,
      });
      upstreamResponse = await forwardToSupabase({
        req,
        supabaseUrl,
        supabaseAnonKey,
        path: `/rest/v1/rpc/${encodeURIComponent(rpc)}`,
        method: 'POST',
        body: params,
      });
    } else if (kind === 'table') {
      const action = String(body.action || '').trim().toLowerCase();
      const table = String(body.table || '').trim();
      if (!table) {
        logWarning('proxy.data.invalid_table_name', {
          requestId: context.requestId,
          bodyKeys: listObjectKeys(body),
          durationMs: durationMs(context),
        });
        json(res, 400, {
          code: 'INVALID_TABLE_NAME',
          message: 'table is required',
        });
        return;
      }
      if (!allowedTables.has(table)) {
        logWarning('proxy.data.table_not_allowed', {
          requestId: context.requestId,
          table,
          action,
          durationMs: durationMs(context),
        });
        json(res, 403, {
          code: 'TABLE_NOT_ALLOWED',
          message: `Table "${table}" is not allowed`,
        });
        return;
      }

      const filters = Array.isArray(body.filters) ? body.filters : [];
      const filterSummary = summarizeFilters(filters);
      const search = new URLSearchParams();
      for (const rawFilter of filters) {
        const filter =
          rawFilter && typeof rawFilter === 'object' ? rawFilter : {};
        const column = String(filter.column || '').trim();
        if (!column) continue;
        const expr = encodeFilterExpression(filter.op, filter.value);
        if (!expr) {
          logWarning('proxy.data.unsupported_filter_op', {
            requestId: context.requestId,
            table,
            action,
            column,
            op: String(filter.op || ''),
            durationMs: durationMs(context),
          });
          json(res, 400, {
            code: 'UNSUPPORTED_FILTER_OP',
            message: `Unsupported filter op "${filter.op}"`,
          });
          return;
        }
        search.append(column, expr);
      }

      if (action === 'select') {
        const columns = String(body.columns || '*').trim() || '*';
        search.set('select', columns);
        const orderClause = buildOrderClause(body.orders);
        if (orderClause) {
          search.set('order', orderClause);
        }
        if (Number.isInteger(body.limit) && body.limit > 0) {
          search.set('limit', String(body.limit));
        }
        operationSummary = {
          kind,
          table,
          action,
          columns,
          limit: Number.isInteger(body.limit) && body.limit > 0
            ? body.limit
            : undefined,
          filters: filterSummary,
          orders: summarizeOrders(body.orders),
        };
        logInfo('proxy.data.forwarding_table_select', {
          requestId: context.requestId,
          ...operationSummary,
        });
        upstreamResponse = await forwardToSupabase({
          req,
          supabaseUrl,
          supabaseAnonKey,
          path: `/rest/v1/${encodeURIComponent(table)}`,
          method: 'GET',
          searchParams: search,
        });
      } else if (action === 'update') {
        const values =
          body.values && typeof body.values === 'object' ? body.values : {};
        const returning = body.returning === true;
        const columns = String(body.columns || '*').trim() || '*';
        if (returning) {
          search.set('select', columns);
        }
        operationSummary = {
          kind,
          table,
          action,
          returning,
          columns: returning ? columns : undefined,
          filters: filterSummary,
          values: summarizeValues(values),
        };
        logInfo('proxy.data.forwarding_table_update', {
          requestId: context.requestId,
          ...operationSummary,
        });
        upstreamResponse = await forwardToSupabase({
          req,
          supabaseUrl,
          supabaseAnonKey,
          path: `/rest/v1/${encodeURIComponent(table)}`,
          method: 'PATCH',
          searchParams: search,
          body: values,
          prefer: returning ? 'return=representation' : 'return=minimal',
        });
      } else if (action === 'upsert') {
        const values = body.values;
        const onConflict = String(body.onConflict || '').trim();
        const returning = body.returning === true;
        const columns = String(body.columns || '*').trim() || '*';
        if (onConflict) {
          search.set('on_conflict', onConflict);
        }
        if (returning) {
          search.set('select', columns);
        }
        const prefer = returning
          ? 'resolution=merge-duplicates,return=representation'
          : 'resolution=merge-duplicates,return=minimal';
        operationSummary = {
          kind,
          table,
          action,
          onConflict: onConflict || undefined,
          returning,
          columns: returning ? columns : undefined,
          values: summarizeValues(values),
        };
        logInfo('proxy.data.forwarding_table_upsert', {
          requestId: context.requestId,
          ...operationSummary,
        });
        upstreamResponse = await forwardToSupabase({
          req,
          supabaseUrl,
          supabaseAnonKey,
          path: `/rest/v1/${encodeURIComponent(table)}`,
          method: 'POST',
          searchParams: search,
          body: values,
          prefer,
        });
      } else {
        logWarning('proxy.data.invalid_table_action', {
          requestId: context.requestId,
          table,
          action,
          durationMs: durationMs(context),
        });
        json(res, 400, {
          code: 'INVALID_TABLE_ACTION',
          message: 'action must be one of: select, update, upsert',
        });
        return;
      }
    } else {
      logWarning('proxy.data.invalid_proxy_kind', {
        requestId: context.requestId,
        kind,
        bodyKeys: listObjectKeys(body),
        durationMs: durationMs(context),
      });
      json(res, 400, {
        code: 'INVALID_PROXY_KIND',
        message: 'kind must be "rpc" or "table"',
      });
      return;
    }
  } catch (error) {
    logError('proxy.data.upstream_request_failed', {
      requestId: context.requestId,
      durationMs: durationMs(context),
      operation: operationSummary,
      error: safeError(error),
    });
    json(res, 502, {
      code: 'UPSTREAM_REQUEST_FAILED',
      message: error instanceof Error ? error.message : 'Unknown proxy error',
    });
    return;
  }

  const contentType =
    upstreamResponse.headers.get('content-type') ||
    'application/json; charset=utf-8';
  const rawText = await upstreamResponse.text();
  const responseBody = rawText.trim().length === 0 ? '{}' : rawText;
  if (upstreamResponse.status >= 400) {
    logWarning('proxy.data.upstream_failed', {
      requestId: context.requestId,
      durationMs: durationMs(context),
      operation: operationSummary,
      upstreamStatus: upstreamResponse.status,
      contentType,
      responsePreview: truncate(responseBody, 240),
    });
  } else {
    logInfo('proxy.data.upstream_succeeded', {
      requestId: context.requestId,
      durationMs: durationMs(context),
      operation: operationSummary,
      upstreamStatus: upstreamResponse.status,
      contentType,
    });
  }
  res.status(upstreamResponse.status);
  res.setHeader('Content-Type', contentType);
  res.send(responseBody);
};
