#!/usr/bin/env node
// Render the upstream router projection, then apply this consumer's Cloudflare runtime date.
// The upstream renderer owns routes, bindings, and ROUTER_CONFIG; this wrapper owns the
// compatibility-date policy so it can be reviewed and tested without hand-editing generated TOML.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const consumerRoot = resolve(here, "..");
const configArg = process.argv[2] ?? "router.config.json";
const outputPath = resolve(consumerRoot, "wrangler.toml");
const compatibilityDatePath = resolve(here, "..", "compatibility-date.txt");
const upstreamRenderer = resolve(
  here,
  "..",
  "node_modules/@oresoftware/ores-edge-router/scripts/render-wrangler.mjs",
);

const compatibilityDate = readFileSync(compatibilityDatePath, "utf8").trim();
if (!/^\d{4}-\d{2}-\d{2}$/.test(compatibilityDate)) {
  console.error(`invalid compatibility-date.txt: ${compatibilityDate}`);
  process.exit(2);
}

const result = spawnSync(
  process.execPath,
  [upstreamRenderer, configArg, "--out", "wrangler.toml"],
  { cwd: consumerRoot, stdio: "inherit" },
);
if (result.status !== 0) process.exit(result.status ?? 1);

const rendered = readFileSync(outputPath, "utf8");
const withDate = rendered.replace(
  /^compatibility_date = "[^"]+"$/m,
  `compatibility_date = "${compatibilityDate}"`,
);
if (withDate === rendered) {
  console.error("upstream renderer did not emit compatibility_date");
  process.exit(1);
}
writeFileSync(outputPath, withDate);
