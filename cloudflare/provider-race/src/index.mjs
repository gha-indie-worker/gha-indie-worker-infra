const DEFAULT_DEADLINE_MS = 2500;
const MAX_DEADLINE_MS = 10_000;
const MAX_URL_BYTES = 4096;
const ALLOWED_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

export default {
  fetch(request, env) {
    return handleRequest(request, env, fetch);
  },
};

export async function handleRequest(request, env, fetchImpl) {
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        allow: "GET, HEAD, OPTIONS",
        "cache-control": "no-store",
      },
    });
  }

  if (!ALLOWED_METHODS.has(request.method)) {
    return json(405, { error: "read_only_provider_race" }, {
      allow: "GET, HEAD, OPTIONS",
    });
  }

  let providers;
  try {
    providers = providerOrigins(env);
  } catch {
    return json(503, { error: "provider_race_misconfigured" });
  }

  const incoming = new URL(request.url);
  if (incoming.pathname === "/healthz" || incoming.pathname === "/readyz") {
    const health = await probeProviders(providers, env, fetchImpl);
    return json(health.healthy.length > 0 ? 200 : 503, health);
  }

  const deadlineMs = boundedDeadline(env.GIW_PROVIDER_RACE_DEADLINE_MS);
  const controllers = providers.map(() => new AbortController());
  let timer;
  try {
    const winner = await firstSuccessful(
      providers.map((provider, index) =>
        forwardRead(request, incoming, provider, fetchImpl, controllers[index].signal)
      ),
      deadlineMs,
    );
    controllers.forEach((controller, index) => {
      if (index !== winner.index) controller.abort("provider_race_lost");
    });
    const headers = new Headers(winner.response.headers);
    harden(headers);
    headers.set("x-giw-db-origin", winner.provider.name);
    headers.set("x-giw-provider-race", "winner");
    return new Response(winner.response.body, {
      status: winner.response.status,
      statusText: winner.response.statusText,
      headers,
    });
  } catch {
    return json(503, { error: "provider_race_unavailable" }, { "retry-after": "1" });
  } finally {
    if (timer) clearTimeout(timer);
    controllers.forEach((controller) => controller.abort("provider_race_complete"));
  }
}

export function providerOrigins(env) {
  return [
    { name: "supabase", url: requiredHttpsUrl(env.SUPABASE_ORIGIN, "SUPABASE_ORIGIN") },
    { name: "neon", url: requiredHttpsUrl(env.NEON_ORIGIN, "NEON_ORIGIN") },
  ];
}

async function forwardRead(request, incoming, provider, fetchImpl, signal) {
  const target = new URL(provider.url);
  const prefix = target.pathname.replace(/\/$/, "");
  target.pathname = joinPath(prefix, incoming.pathname);
  target.search = incoming.search;
  if (target.toString().length > MAX_URL_BYTES) throw new Error("target_too_large");

  const headers = sanitizedHeaders(request.headers);
  headers.set("x-giw-db-origin-requested", provider.name);
  const response = await fetchImpl(new Request(target, {
    method: request.method,
    headers,
    redirect: "manual",
    signal,
  }));
  if (response.status < 200 || response.status >= 400) {
    throw new Error(`provider_${provider.name}_status_${response.status}`);
  }
  return { provider, response };
}

async function firstSuccessful(promises, deadlineMs) {
  return new Promise((resolve, reject) => {
    let pending = promises.length;
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error("provider_race_timeout"));
      }
    }, deadlineMs);

    promises.forEach((promise, index) => {
      Promise.resolve(promise).then(
        (value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve({ ...value, index });
        },
        () => {
          pending -= 1;
          if (!settled && pending === 0) {
            settled = true;
            clearTimeout(timer);
            reject(new Error("provider_race_failed"));
          }
        },
      );
    });
  });
}

async function probeProviders(providers, env, fetchImpl) {
  const deadlineMs = Math.min(1500, boundedDeadline(env.GIW_PROVIDER_RACE_DEADLINE_MS));
  const results = await Promise.all(providers.map(async (provider) => {
    const target = new URL(provider.url);
    target.pathname = joinPath(target.pathname.replace(/\/$/, ""), "/healthz");
    target.search = "";
    try {
      const response = await fetchImpl(target, {
        method: "GET",
        redirect: "manual",
        signal: AbortSignal.timeout(deadlineMs),
      });
      return { name: provider.name, ok: response.status >= 200 && response.status < 400 };
    } catch {
      return { name: provider.name, ok: false };
    }
  }));
  return {
    ok: results.some((result) => result.ok),
    component: "gha-indie-worker-provider-race",
    healthy: results.filter((result) => result.ok).map((result) => result.name),
    configured: providers.map((provider) => provider.name),
  };
}

function sanitizedHeaders(input) {
  const headers = new Headers(input);
  for (const name of [
    "host",
    "cf-connecting-ip",
    "cf-ray",
    "x-forwarded-for",
    "x-forwarded-host",
    "x-forwarded-proto",
    "x-real-ip",
    "x-giw-db-origin",
    "x-giw-db-origin-requested",
    "x-giw-provider-race",
  ]) headers.delete(name);
  headers.set("accept", headers.get("accept") || "application/json");
  return headers;
}

function requiredHttpsUrl(raw, name) {
  const value = String(raw || "").trim();
  const url = new URL(value);
  if (
    url.protocol !== "https:"
    || url.username
    || url.password
    || url.search
    || url.hash
  ) {
    throw new Error(`${name} must be a credential-free HTTPS origin`);
  }
  return url;
}

function boundedDeadline(raw) {
  const parsed = raw == null || raw === "" ? DEFAULT_DEADLINE_MS : Number(raw);
  if (!Number.isInteger(parsed) || parsed < 100 || parsed > MAX_DEADLINE_MS) {
    throw new Error("invalid race deadline");
  }
  return parsed;
}

function joinPath(prefix, suffix) {
  const left = prefix.replace(/\/$/, "");
  const right = suffix.startsWith("/") ? suffix : `/${suffix}`;
  return `${left}${right}` || "/";
}

function harden(headers) {
  headers.set("cache-control", "no-store");
  headers.set("x-content-type-options", "nosniff");
  headers.set("referrer-policy", "no-referrer");
}

function json(status, body, extraHeaders = {}) {
  const headers = new Headers({
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "referrer-policy": "no-referrer",
    ...extraHeaders,
  });
  return new Response(JSON.stringify(body), { status, headers });
}
