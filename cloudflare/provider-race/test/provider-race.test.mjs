import test from "node:test";
import assert from "node:assert/strict";

import { handleRequest, providerOrigins } from "../src/index.mjs";

const env = {
  SUPABASE_ORIGIN: "https://supabase-adapter.example",
  NEON_ORIGIN: "https://neon-adapter.example",
  GIW_PROVIDER_RACE_DEADLINE_MS: "500",
};

test("first successful provider wins even when the other fails faster", async () => {
  const calls = [];
  const fetchImpl = async (request) => {
    const url = new URL(request.url ?? request);
    calls.push(url.hostname);
    if (url.hostname.startsWith("supabase")) {
      return new Response("down", { status: 503 });
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
    return new Response(JSON.stringify({ provider: "neon" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  const response = await handleRequest(
    new Request("https://db.indiebuild.dev/v1/projects?id=eq.1"),
    env,
    fetchImpl,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-giw-db-origin"), "neon");
  assert.deepEqual(new Set(calls), new Set([
    "supabase-adapter.example",
    "neon-adapter.example",
  ]));
});

test("mutations are never duplicated behind the race", async () => {
  let calls = 0;
  const response = await handleRequest(
    new Request("https://db.indiebuild.dev/v1/projects", { method: "POST", body: "{}" }),
    env,
    async () => {
      calls += 1;
      return new Response("unexpected");
    },
  );

  assert.equal(response.status, 405);
  assert.equal(calls, 0);
});

test("provider origins must be credential-free https URLs", () => {
  assert.throws(() => providerOrigins({
    ...env,
    SUPABASE_ORIGIN: "https://user:secret@example.com",
  }));
  assert.throws(() => providerOrigins({
    ...env,
    NEON_ORIGIN: "http://127.0.0.1:9999",
  }));
});
