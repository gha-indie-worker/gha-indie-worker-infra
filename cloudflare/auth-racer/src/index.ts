interface Env {
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  NEON_AUTH_ORIGIN: string;
  NEON_AUTH_SHARED_SECRET?: string;
  AUTH_RACE_TIMEOUT_MS?: string;
}

type VerifiedIdentity = {
  ok: true;
  authority: "supabase" | "neon";
  user: unknown;
};

type VerifyFailure = {
  ok: false;
  authority: "supabase" | "neon";
  status: number;
};

function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      ...headers,
    },
  });
}

function timeoutMs(env: Env): number {
  const parsed = Number(env.AUTH_RACE_TIMEOUT_MS ?? "1800");
  return Number.isFinite(parsed) && parsed >= 100 && parsed <= 5000 ? parsed : 1800;
}

async function readJsonBounded(response: Response, maxBytes = 256 * 1024): Promise<unknown> {
  const contentLength = Number(response.headers.get("content-length") ?? "0");
  if (contentLength > maxBytes) throw new Error("response too large");
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) throw new Error("response too large");
  return text ? JSON.parse(text) : null;
}

async function verifySupabase(
  request: Request,
  env: Env,
  signal: AbortSignal,
): Promise<VerifiedIdentity | VerifyFailure> {
  const authorization = request.headers.get("authorization");
  if (!authorization) return { ok: false, authority: "supabase", status: 401 };

  const response = await fetch(new URL("/auth/v1/user", env.SUPABASE_URL), {
    method: "GET",
    headers: {
      authorization,
      apikey: env.SUPABASE_ANON_KEY,
      accept: "application/json",
    },
    redirect: "manual",
    signal,
  });

  if (!response.ok) {
    return { ok: false, authority: "supabase", status: response.status };
  }

  return {
    ok: true,
    authority: "supabase",
    user: await readJsonBounded(response),
  };
}

async function verifyNeon(
  request: Request,
  env: Env,
  signal: AbortSignal,
): Promise<VerifiedIdentity | VerifyFailure> {
  const authorization = request.headers.get("authorization");
  if (!authorization) return { ok: false, authority: "neon", status: 401 };

  const headers = new Headers({
    authorization,
    accept: "application/json",
  });
  if (env.NEON_AUTH_SHARED_SECRET) {
    headers.set("x-giw-auth-racer-secret", env.NEON_AUTH_SHARED_SECRET);
  }

  const response = await fetch(new URL("/v1/auth/verify", env.NEON_AUTH_ORIGIN), {
    method: "GET",
    headers,
    redirect: "manual",
    signal,
  });

  if (!response.ok) {
    return { ok: false, authority: "neon", status: response.status };
  }

  return {
    ok: true,
    authority: "neon",
    user: await readJsonBounded(response),
  };
}

async function firstVerified(
  request: Request,
  env: Env,
): Promise<VerifiedIdentity | null> {
  const timeout = timeoutMs(env);
  const supabaseController = new AbortController();
  const neonController = new AbortController();

  const timer = setTimeout(() => {
    supabaseController.abort("auth race timeout");
    neonController.abort("auth race timeout");
  }, timeout);

  const candidates = [
    verifySupabase(request, env, supabaseController.signal),
    verifyNeon(request, env, neonController.signal),
  ];

  try {
    const pending = new Set(candidates);
    while (pending.size) {
      const tagged = [...pending].map((promise) =>
        promise.then(
          (value) => ({ promise, value }),
          () => ({ promise, value: null }),
        ),
      );
      const { promise, value } = await Promise.race(tagged);
      pending.delete(promise);
      if (value?.ok) {
        if (value.authority === "supabase") neonController.abort("race won");
        else supabaseController.abort("race won");
        return value;
      }
    }
    return null;
  } finally {
    clearTimeout(timer);
    supabaseController.abort("request complete");
    neonController.abort("request complete");
  }
}

async function proxySupabaseAuth(request: Request, env: Env): Promise<Response> {
  const incoming = new URL(request.url);
  const upstream = new URL(incoming.pathname.replace(/^\/auth/, "/auth/v1"), env.SUPABASE_URL);
  upstream.search = incoming.search;

  const headers = new Headers(request.headers);
  headers.set("apikey", env.SUPABASE_ANON_KEY);
  headers.delete("host");
  headers.delete("cf-connecting-ip");
  headers.delete("x-forwarded-for");

  return fetch(upstream, {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? undefined : request.body,
    redirect: "manual",
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/healthz" || url.pathname === "/readyz") {
      return json({ ok: true, service: "gha-indie-worker-auth-racer" });
    }

    if (url.pathname === "/v1/auth/verify") {
      const verified = await firstVerified(request, env);
      if (!verified) return json({ ok: false, error: "unauthenticated" }, 401);
      return json(verified, 200, { "x-auth-authority": verified.authority });
    }

    // Signup/login/refresh are intentionally single-authority writes. We do not
    // duplicate or race writes across Supabase and Neon because that can create
    // split-brain identities. Neon receives product/session projections through
    // the backend's idempotent persistence path.
    if (url.pathname.startsWith("/auth/")) {
      return proxySupabaseAuth(request, env);
    }

    return json({ error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;
