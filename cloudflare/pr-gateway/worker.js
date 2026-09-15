const MAX_BODY_BYTES = 1024 * 1024;

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/healthz") {
      return json(200, { ok: true, service: "indiebuild-pr-edge" });
    }
    if (url.pathname !== "/webhooks/github") {
      return json(404, { error: "not found" });
    }
    if (request.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    if (!env.PR_GATEWAY_ORIGIN) {
      return json(503, { error: "PR_GATEWAY_ORIGIN is not configured" });
    }

    const declaredLength = Number(request.headers.get("content-length") || "0");
    if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
      return json(413, { error: "webhook body too large" });
    }

    const body = await request.arrayBuffer();
    if (body.byteLength > MAX_BODY_BYTES) {
      return json(413, { error: "webhook body too large" });
    }

    const upstream = new URL(env.PR_GATEWAY_ORIGIN);
    upstream.pathname = "/webhooks/github";
    upstream.search = "";
    if (upstream.protocol !== "https:") {
      return json(503, { error: "PR_GATEWAY_ORIGIN must use https" });
    }

    const headers = new Headers(request.headers);
    headers.set("x-ores-edge", "gha-indie-worker-pr-gateway");
    headers.delete("content-length");

    return fetch(upstream.toString(), {
      method: "POST",
      headers,
      body,
      redirect: "manual",
    });
  },
};
