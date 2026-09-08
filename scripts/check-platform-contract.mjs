#!/usr/bin/env node
// Static, credential-free guard for the indiebuild.dev edge + Cloud Run contract.
// This intentionally checks the source projections rather than provider state. Provider
// acceptance still requires a separately authorized, read-only live audit.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const text = (root, relativePath) => readFileSync(resolve(root, relativePath), "utf8");

const requiredHosts = new Set([
  "app",
  "user",
  "org",
  "m",
  "api",
  "auth",
  "admin",
  "admin-api",
  "api-admin",
  "www",
]);
const adminHosts = ["admin", "admin-api", "api-admin"];
const productFallbackHosts = ["app", "user", "org", "m", "api"];
const expectedServices = [
  "gha-indie-worker-web-server",
  "gha-indie-worker-api-server",
  "gha-indie-worker-admin-web-server",
  "gha-indie-worker-admin-api-server",
  "gha-indie-worker-mcp-server",
];

const cloudRunResource = (source, name) => {
  const marker = `resource "google_cloud_run_v2_service" "${name}"`;
  const start = source.indexOf(marker);
  if (start < 0) return "";
  const next = source.indexOf("\nresource ", start + marker.length);
  return source.slice(start, next < 0 ? source.length : next);
};

export function checkPlatformContract(root) {
  const problems = [];
  const router = JSON.parse(text(root, "cloudflare/edge-router/router.config.json"));
  if (router.org !== "gha-indie-worker") problems.push(`router org is ${router.org}`);
  if (router.domain !== "indiebuild.dev") problems.push(`router domain is ${router.domain}`);

  const hosts = new Set(Object.keys(router.hosts ?? {}));
  for (const host of requiredHosts) {
    if (!hosts.has(host)) problems.push(`router is missing required host ${host}`);
  }
  for (const host of hosts) {
    const config = router.hosts[host];
    if (!config.primary?.url?.startsWith("https://")) {
      problems.push(`${host} primary must be HTTPS`);
    }
  }
  for (const host of adminHosts) {
    const config = router.hosts[host];
    if (config.access !== "cloudflare-access") problems.push(`${host} is not Access-gated`);
    if (config.fallback !== undefined) problems.push(`${host} must not have a fallback`);
  }
  for (const host of productFallbackHosts) {
    const fallback = router.hosts[host]?.fallback;
    if (!fallback || fallback.kind !== "cloudrun") {
      problems.push(`${host} must have a Cloud Run fallback`);
    }
  }
  if (router.hosts.api?.websocket !== true) problems.push("api websocket forwarding is disabled");

  const dns = text(root, "cloudflare/dns/variables.tf");
  const proxiedHosts = dns.match(/default\s*=\s*\[([^\]]+)\]/s)?.[1] ?? "";
  for (const host of [...requiredHosts].filter((host) => host !== "www")) {
    if (!new RegExp(`\\"${host}\\"`).test(proxiedHosts)) {
      problems.push(`Cloudflare DNS does not proxy ${host}`);
    }
  }

  const compatibilityDate = text(root, "cloudflare/edge-router/compatibility-date.txt").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(compatibilityDate)) {
    problems.push("Cloudflare compatibility-date.txt is not YYYY-MM-DD");
  } else {
    const ageDays = (Date.now() - Date.parse(`${compatibilityDate}T00:00:00Z`)) / 86_400_000;
    if (ageDays < -1 || ageDays > 31) {
      problems.push(`Cloudflare compatibility date is ${Math.round(ageDays)} days from today`);
    }
  }

  const services = text(root, "gcp/cloudrun/services.tf");
  for (const service of expectedServices) {
    if (!new RegExp(`name\\s*=\\s*"${service}"`).test(services)) {
      problems.push(`Cloud Run service missing: ${service}`);
    }
  }
  for (const name of ["web", "api"]) {
    const resource = cloudRunResource(services, name);
    if (!resource.includes("invoker_iam_disabled = true")) {
      problems.push(`product Cloud Run ${name} must accept edge invocation explicitly`);
    }
  }
  for (const name of ["admin_api", "admin_web", "mcp"]) {
    const resource = cloudRunResource(services, name);
    if (!/ingress\s*=\s*"INGRESS_TRAFFIC_INTERNAL_ONLY"/.test(resource)) {
      problems.push(`admin Cloud Run ${name} is not internal-only`);
    }
  }
  for (const name of ["admin_api", "admin_web"]) {
    const resource = cloudRunResource(services, name);
    if (!/deletion_protection\s*=\s*true/.test(resource)) {
      problems.push(`admin Cloud Run ${name} lacks deletion protection`);
    }
  }
  if (/^\s*member\s*=\s*"allUsers"/m.test(services)) {
    problems.push("Cloud Run service IAM must not grant allUsers");
  }
  if (/REPLACE/.test(services)) problems.push("Cloud Run service environment contains a placeholder");

  const iam = text(root, "gcp/cloudrun/iam.tf");
  if (/member\s*=\s*"allUsers"/.test(iam)) problems.push("IAM grants allUsers");
  const secrets = text(root, "gcp/cloudrun/secrets.tf");
  const productSecretGrant = secrets.match(
    /resource\s+"google_secret_manager_secret_iam_member"\s+"product_access"\s*\{([\s\S]*?)\n\}/,
  )?.[1] ?? "";
  if (/google_secret_manager_secret\.admin/.test(productSecretGrant)) {
    problems.push("product secret grants mention admin");
  }
  if (!secrets.includes('"giw-admin-database-url"')) problems.push("admin database secret is undeclared");

  return problems;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const root = resolve(new URL("..", import.meta.url).pathname);
  const problems = checkPlatformContract(root);
  if (problems.length) {
    console.error("platform contract FAILED:");
    for (const problem of problems) console.error(`  - ${problem}`);
    process.exit(1);
  }
  console.log("platform contract ok: indiebuild.dev hosts, Cloud Run planes, and edge policy");
}
