#!/usr/bin/env node
// Structural checks on .db-providers.json that a JSON Schema cannot express well:
// the two planes must be disjoint, and no product service may be listed as able to reach an
// admin-role database. Fails closed.
import { readFileSync } from "node:fs";

const cfg = JSON.parse(readFileSync(new URL("../.db-providers.json", import.meta.url), "utf8"));
const problems = [];

const planes = cfg.planes ?? {};
const product = planes.product ?? { services: [], mayReach: [] };
const admin = planes.admin ?? { services: [], mayReach: [] };

const overlap = product.services.filter((s) => admin.services.includes(s));
if (overlap.length) problems.push(`a service is in both planes: ${overlap.join(", ")}`);

for (const target of product.mayReach ?? []) {
  if (target.includes("admin")) problems.push(`product plane may not reach ${target}`);
}
for (const target of admin.mayReach ?? []) {
  if (/(canonical|:auth)$/.test(target)) problems.push(`admin plane may not reach ${target}`);
}

const byRole = (list) => Object.fromEntries((list ?? []).map((p) => [p.role, p]));
const neon = byRole(cfg.neon?.projects);
const supa = byRole(cfg.supabase?.projects);

for (const role of ["canonical", "auth", "admin"]) {
  if (!neon[role]) problems.push(`neon: no project with role ${role}`);
  if (!supa[role]) problems.push(`supabase: no project with role ${role}`);
}

// The admin Neon project must stay closed while it has no accepted private endpoint.
const neonAdmin = neon.admin ?? {};
if (neonAdmin.state === "active" && (!neonAdmin.publicConnectionsBlocked || !neonAdmin.vpcConnectionsBlocked)) {
  if (!Array.isArray(neonAdmin.acceptanceEvidence) || neonAdmin.acceptanceEvidence.length < 4) {
    problems.push(
      "neon admin project is marked active with connections open but carries no acceptanceEvidence[] " +
        "(needs: private endpoint, admin-network success, product-network refusal, public refusal)",
    );
  }
}

// A project that is not yet provisioned must say what it is blocked on, so the gap stays a
// decision and not a mystery.
for (const [provider, list] of [
  ["neon", cfg.neon?.projects],
  ["supabase", cfg.supabase?.projects],
]) {
  for (const p of list ?? []) {
    if ((p.state === "planned" || p.ref === null || p.id === null) && !(p.blockedOn ?? []).length) {
      problems.push(`${provider}:${p.slug} is not provisioned and has no blockedOn[]`);
    }
  }
}

if (problems.length) {
  console.error("db-providers check FAILED:");
  for (const p of problems) console.error(`  - ${p}`);
  process.exit(1);
}
console.log(
  `db-providers ok: neon ${Object.keys(neon).join("/")}, supabase ${Object.keys(supa).join("/")}, planes disjoint`,
);
